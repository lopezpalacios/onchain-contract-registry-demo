#!/usr/bin/env python3
"""Local demo API + static UI for the Smart Contract Registry.

Run:
    python3 app.py
    open http://127.0.0.1:8765

This is a local prototype. It intentionally has no authentication, TLS or
production hardening. Do not expose it outside a demo machine.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import sqlite3
import sys
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "data" / "registry.db"
WEB_ROOT = ROOT / "web"
sys.path.insert(0, str(ROOT / "registry"))
sys.path.insert(0, str(ROOT / "scripts"))
from keccak import eip55  # noqa: E402
from besu_sync import run_mock  # noqa: E402


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class RegistryDB:
    def __init__(self, path: Path):
        self.path = path

    def connect(self):
        conn = sqlite3.connect(self.path, timeout=10)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn


def rowdict(row) -> dict:
    if row is None:
        return {}
    data = dict(row)
    if "address" in data and data["address"]:
        try:
            data["address_eip55"] = eip55(data["address"])
        except ValueError:
            data["address_eip55"] = data["address"]
    return data


def rows(conn, sql, params=()):
    return [rowdict(r) for r in conn.execute(sql, params).fetchall()]


def one(conn, sql, params=()):
    return rowdict(conn.execute(sql, params).fetchone())


def scalar(conn, sql, params=()):
    row = conn.execute(sql, params).fetchone()
    return row[0] if row else None


def org_ancestors(conn, org_unit_id: str) -> set[str]:
    if not org_unit_id:
        return set()
    result = conn.execute(
        """
        WITH RECURSIVE ancestors(id, parent_id) AS (
            SELECT id, parent_id FROM org_unit WHERE id = ?
            UNION ALL
            SELECT o.id, o.parent_id FROM org_unit o JOIN ancestors a ON o.id = a.parent_id
        )
        SELECT id FROM ancestors
        """,
        (org_unit_id,),
    ).fetchall()
    return {r["id"] for r in result}


def person_has_role(conn, person_id: str, role_code: str, org_unit_id: str | None = None) -> bool:
    if not person_id:
        return False
    assignments = conn.execute(
        """
        SELECT ra.scope_org_unit_id, ra.valid_from, ra.valid_to
        FROM role_assignment ra
        JOIN person p ON p.id = ra.person_id
        WHERE ra.person_id = ? AND ra.role_code = ? AND ra.active = 1 AND p.active = 1
        """,
        (person_id, role_code),
    ).fetchall()
    if not assignments:
        return False
    allowed_orgs = org_ancestors(conn, org_unit_id) if org_unit_id else set()
    today = utcnow()[:10]
    for assignment in assignments:
        if assignment["valid_from"] and assignment["valid_from"] > today:
            continue
        if assignment["valid_to"] and assignment["valid_to"] < today:
            continue
        scope = assignment["scope_org_unit_id"]
        if scope is None or not org_unit_id or scope in allowed_orgs:
            return True
    return False


def eligible_actors(conn, role_code: str, org_unit_id: str | None = None):
    people = conn.execute(
        """
        SELECT DISTINCT p.id, p.display_name, p.email, p.title, ou.name AS org_unit
        FROM role_assignment ra
        JOIN person p ON p.id = ra.person_id
        LEFT JOIN org_unit ou ON ou.id = p.org_unit_id
        WHERE ra.role_code = ? AND ra.active = 1 AND p.active = 1
        ORDER BY p.display_name
        """,
        (role_code,),
    ).fetchall()
    return [rowdict(p) for p in people if person_has_role(conn, p["id"], role_code, org_unit_id)]


# ---------------------------------------------------------------------------
# Read models
# ---------------------------------------------------------------------------


def summary(conn) -> dict:
    logical = scalar(conn, "SELECT COUNT(*) FROM contract_instance WHERE instance_kind='logical'") or 0
    unlinked = scalar(
        conn, "SELECT COUNT(*) FROM discovery_queue WHERE status IN ('new','triage','quarantined')"
    ) or 0
    observed = logical + unlinked
    risk = rows(
        conn,
        """
        SELECT risk_tier, COUNT(*) AS count
        FROM contract_instance WHERE instance_kind='logical'
        GROUP BY risk_tier
        ORDER BY CASE risk_tier WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END
        """,
    )
    reserve = one(
        conn,
        """
        SELECT
            SUM(CASE WHEN counts_toward_reserve = 1 THEN total_supply ELSE 0 END) AS supply,
            SUM(CASE WHEN counts_toward_reserve = 1 THEN gold_grams ELSE 0 END) AS gold
        FROM v_token_reserve WHERE reserve_state = 'current'
        """,
    )
    supply = reserve.get("supply") or 0
    gold = reserve.get("gold") or 0
    coverage = (gold / supply * 100) if supply else 0
    approvals = rows(
        conn,
        "SELECT * FROM v_pending_approvals WHERE status = 'in_review' ORDER BY created_at ASC",
    )
    return {
        "generated_at": utcnow(),
        "counts": {
            "logical_instances": logical,
            "observed_contracts": observed,
            "templates": scalar(conn, "SELECT COUNT(*) FROM template") or 0,
            "templates_approved": scalar(conn, "SELECT COUNT(*) FROM template WHERE status='approved'") or 0,
            "chains": scalar(conn, "SELECT COUNT(*) FROM chain") or 0,
            "pending_gates": scalar(conn, "SELECT COUNT(*) FROM signoff WHERE decision='pending'") or 0,
            "unlinked": unlinked,
            "expiring_attestations": scalar(
                conn,
                """
                SELECT COUNT(*) FROM attestation
                WHERE status='valid' AND expires_at IS NOT NULL
                  AND date(expires_at) <= date('now', '+60 days')
                """,
            ) or 0,
            "critical_high": scalar(
                conn,
                "SELECT COUNT(*) FROM contract_instance WHERE instance_kind='logical' AND risk_tier IN ('high','critical')",
            ) or 0,
            "control_exceptions": scalar(
                conn, "SELECT COUNT(*) FROM instance_control WHERE status IN ('fail','exception')"
            ) or 0,
            "open_findings": scalar(
                conn, "SELECT COUNT(*) FROM persona_finding WHERE status='open'"
            ) or 0,
            "council_high_open": scalar(
                conn,
                "SELECT COUNT(*) FROM persona_finding WHERE status='open' AND severity IN ('critical','high')",
            ) or 0,
        },
        "coverage": {
            "registered": logical,
            "observed": observed,
            "percent": round((logical / observed * 100), 1) if observed else 0,
        },
        "risk": risk,
        "reserve": {
            "supply_grams": supply,
            "gold_grams": gold,
            "coverage_percent": round(coverage, 2),
        },
        "control_pass_percent": scalar(
            conn,
            """
            SELECT ROUND(100.0 * SUM(CASE WHEN status='pass' THEN 1 ELSE 0 END) /
                         NULLIF(SUM(CASE WHEN status IN ('pass','fail','exception') THEN 1 ELSE 0 END), 0), 1)
            FROM instance_control
            """,
        ) or 0,
        "chains": rows(conn, "SELECT * FROM v_chain_health ORDER BY name"),
        "approvals": approvals[:5],
        "alerts": rows(conn, "SELECT * FROM v_attestation_alerts ORDER BY expires_at ASC LIMIT 6"),
        "exceptions": rows(conn, "SELECT * FROM v_control_exceptions ORDER BY control_code LIMIT 6"),
        "recent_deployments": rows(conn, "SELECT * FROM v_inventory ORDER BY deployed_at DESC LIMIT 6"),
    }


def inventory(conn, filters: dict) -> list[dict]:
    clauses = []
    params: list = []
    for field in ("risk_tier", "chain_id", "status", "category", "org_unit_id"):
        value = filters.get(field)
        if value:
            clauses.append(f"i.{field} = ?")
            params.append(value)
    if filters.get("q"):
        clauses.append(
            "(lower(i.product_name) LIKE ? OR lower(i.template_name) LIKE ? OR lower(i.address) LIKE ? OR lower(i.business_owner) LIKE ?)"
        )
        needle = f"%{filters['q'].lower()}%"
        params.extend([needle, needle, needle, needle])
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    return rows(conn, f"SELECT * FROM v_inventory i {where} ORDER BY i.risk_tier DESC, i.product_name", params)


def instance_detail(conn, instance_id: str) -> dict | None:
    row = conn.execute(
        """
        SELECT ci.*, ch.name AS chain_name, ch.network_type, ch.environment AS chain_environment,
               t.name AS template_name, t.version AS template_version, t.category, t.contract_type,
               t.audit_status, t.audit_provider, t.audit_valid_until, t.status AS template_status,
               owner.display_name AS business_owner, ou.name AS org_unit, ou.division,
               dr.status AS deployment_status, dr.target_window, dr.change_ticket,
               si.name AS signer_identity, si.key_type AS signer_key_type,
               si.allowlisted AS signer_allowlisted, si.evidence_uri AS signer_evidence_uri
        FROM contract_instance ci
        JOIN chain ch ON ch.id = ci.chain_id
        JOIN template t ON t.id = ci.template_id
        LEFT JOIN person owner ON owner.id = ci.business_owner_id
        LEFT JOIN org_unit ou ON ou.id = ci.org_unit_id
        LEFT JOIN deployment_request dr ON dr.id = ci.deployment_request_id
        LEFT JOIN signing_identity si ON si.id = ci.signing_identity_id
        WHERE ci.id = ?
        """,
        (instance_id,),
    ).fetchone()
    if row is None:
        return None
    data = rowdict(row)
    data["is_logical"] = data["instance_kind"] == "logical"
    data["token"] = one(conn, "SELECT * FROM token_metadata WHERE instance_id = ?", (instance_id,))
    data["reserve"] = one(conn, "SELECT * FROM v_token_reserve WHERE instance_id = ?", (instance_id,))
    data["compliance"] = one(
        conn,
        """
        SELECT cp.*, p.display_name AS reviewed_by_name
        FROM compliance_profile cp
        LEFT JOIN person p ON p.id = cp.reviewed_by
        WHERE cp.instance_id = ?
        """,
        (instance_id,),
    )
    data["signer"] = one(
        conn,
        """
        SELECT si.*, p.display_name AS owner_name
        FROM signing_identity si
        LEFT JOIN person p ON p.id = si.owner_person_id
        WHERE si.id = ?
        """,
        (data.get("signing_identity_id"),),
    )
    data["ict"] = rows(
        conn,
        """
        SELECT ii.dependency_type, ii.critical, ii.evidence_uri,
               tp.id AS provider_id, tp.name AS provider, tp.service,
               tp.criticality, tp.data_location, tp.contract_ref,
               tp.dora_register_ref, tp.exit_plan
        FROM instance_ict ii
        JOIN ict_third_party tp ON tp.id = ii.provider_id
        WHERE ii.instance_id = ?
        ORDER BY tp.criticality, tp.name
        """,
        (instance_id,),
    )
    data["parameters"] = rows(
        conn,
        """
        SELECT ip.*, tp.default_value, tp.description
        FROM instance_parameter ip
        LEFT JOIN template_parameter tp ON tp.template_id = ? AND tp.name = ip.name
        WHERE ip.instance_id = ? ORDER BY ip.name
        """,
        (data["template_id"], instance_id),
    )
    data["roles"] = rows(conn, "SELECT * FROM instance_role WHERE instance_id = ? ORDER BY role_name", (instance_id,))
    data["links"] = rows(
        conn,
        """
        SELECT l.*, f.product_name AS from_name, t.product_name AS to_name,
               t.id AS to_id, f.id AS from_id
        FROM contract_link l
        JOIN contract_instance f ON f.id = l.from_instance_id
        JOIN contract_instance t ON t.id = l.to_instance_id
        WHERE l.from_instance_id = ? OR l.to_instance_id = ?
        ORDER BY l.relation
        """,
        (instance_id, instance_id),
    )
    data["documents"] = rows(
        conn,
        """
        SELECT * FROM document
        WHERE (object_type='instance' AND object_id=?)
           OR (object_type='template' AND object_id=?)
           OR (object_type='deployment_request' AND object_id=?)
        ORDER BY created_at DESC
        """,
        (instance_id, data["template_id"], data["deployment_request_id"]),
    )
    data["attestations"] = rows(
        conn,
        """
        SELECT * FROM attestation
        WHERE instance_id = ? OR template_id = ?
        ORDER BY expires_at IS NULL, expires_at
        """,
        (instance_id, data["template_id"]),
    )
    data["events"] = rows(
        conn,
        "SELECT * FROM onchain_event WHERE instance_id = ? ORDER BY block_number DESC, log_index DESC LIMIT 25",
        (instance_id,),
    )
    data["controls"] = rows(
        conn,
        """
        SELECT ic.*, c.code, c.name, c.framework
        FROM instance_control ic JOIN control c ON c.id = ic.control_id
        WHERE ic.instance_id = ? ORDER BY c.code
        """,
        (instance_id,),
    )
    data["changes"] = rows(
        conn,
        "SELECT * FROM change_request WHERE instance_id = ? ORDER BY created_at DESC",
        (instance_id,),
    )
    data["incidents"] = rows(
        conn,
        "SELECT * FROM incident WHERE instance_id = ? ORDER BY opened_at DESC",
        (instance_id,),
    )
    data["template"] = one(conn, "SELECT * FROM template WHERE id = ?", (data["template_id"],))
    data["template"]["standards"] = rows(
        conn,
        """
        SELECT ts.standard_code, s.name, ts.conformance
        FROM template_standard ts JOIN standard s ON s.code = ts.standard_code
        WHERE ts.template_id = ? ORDER BY s.family, s.code
        """,
        (data["template_id"],),
    )
    if data.get("deployment_request_id"):
        data["signoffs"] = rows(
            conn,
            "SELECT * FROM v_gate_status WHERE object_type='deployment' AND object_id=? ORDER BY sequence",
            (data["deployment_request_id"],),
        )
    else:
        data["signoffs"] = []
    data["audit"] = rows(
        conn,
        """
        SELECT * FROM audit_log
        WHERE (object_type='contract_instance' AND object_id=?)
           OR (object_type='deployment_request' AND object_id=?)
           OR (object_type='discovery_queue' AND object_id IN
               (SELECT id FROM discovery_queue WHERE linked_instance_id = ?))
        ORDER BY at DESC LIMIT 15
        """,
        (instance_id, data.get("deployment_request_id"), instance_id),
    )
    return data


def templates(conn) -> list[dict]:
    data = rows(conn, "SELECT * FROM v_template_usage ORDER BY deployments DESC, name, version")
    for template in data:
        template["standards"] = rows(
            conn,
            "SELECT ts.standard_code, ts.conformance FROM template_standard ts WHERE ts.template_id = ? ORDER BY ts.standard_code",
            (template["id"],),
        )
        template["instances"] = rows(
            conn,
            """
            SELECT id, product_name, chain_id, address, status, risk_tier
            FROM contract_instance
            WHERE template_id = ? AND instance_kind='logical'
            ORDER BY deployed_at DESC
            """,
            (template["id"],),
        )
    return data


def template_detail(conn, template_id: str) -> dict | None:
    row = conn.execute("SELECT * FROM v_template_usage WHERE id = ?", (template_id,)).fetchone()
    if row is None:
        return None
    data = rowdict(row)
    data["standards"] = rows(
        conn,
        """
        SELECT ts.standard_code, s.name, s.family, s.url, ts.conformance, ts.notes
        FROM template_standard ts JOIN standard s ON s.code = ts.standard_code
        WHERE ts.template_id = ? ORDER BY s.family, s.code
        """,
        (template_id,),
    )
    data["parameters"] = rows(
        conn, "SELECT * FROM template_parameter WHERE template_id = ? ORDER BY name", (template_id,)
    )
    data["instances"] = rows(
        conn,
        """
        SELECT ci.*, ch.name AS chain_name
        FROM contract_instance ci JOIN chain ch ON ch.id = ci.chain_id
        WHERE ci.template_id = ? AND ci.instance_kind='logical'
        ORDER BY ci.deployed_at DESC
        """,
        (template_id,),
    )
    data["dependencies"] = rows(
        conn,
        """
        SELECT td.relation, td.version_constraint, t.id, t.name, t.version, t.status
        FROM template_dependency td JOIN template t ON t.id = td.depends_on_template_id
        WHERE td.template_id = ?
        """,
        (template_id,),
    )
    data["documents"] = rows(
        conn,
        "SELECT * FROM document WHERE object_type='template' AND object_id=? ORDER BY created_at DESC",
        (template_id,),
    )
    data["attestations"] = rows(
        conn,
        "SELECT * FROM attestation WHERE template_id=? ORDER BY expires_at IS NULL, expires_at",
        (template_id,),
    )
    data["signoffs"] = rows(
        conn,
        "SELECT * FROM v_gate_status WHERE object_type='template' AND object_id=? ORDER BY sequence",
        (template_id,),
    )
    data["used_by_ci"] = rows(
        conn,
        """
        SELECT sci.id, sci.ci_name, sci.lifecycle_status, sci.criticality
        FROM template_ci tc JOIN software_ci sci ON sci.id = tc.ci_id
        WHERE tc.template_id = ?
        """,
        (template_id,),
    )
    return data


def approvals(conn) -> dict:
    deployments = rows(
        conn,
        "SELECT * FROM v_pending_approvals ORDER BY CASE status WHEN 'in_review' THEN 1 ELSE 2 END, created_at",
    )
    for request in deployments:
        request["gates"] = rows(
            conn,
            "SELECT * FROM v_gate_status WHERE object_type='deployment' AND object_id=? ORDER BY sequence",
            (request["id"],),
        )
        for gate in request["gates"]:
            if gate["decision"] == "pending" and gate["is_next"]:
                gate["eligible_actors"] = eligible_actors(conn, gate["required_role"], request.get("org_unit_id"))
    template_requests = rows(
        conn,
        """
        SELECT t.id, t.name, t.version, t.status, t.default_risk_tier, t.audit_status,
               t.audit_valid_until, t.audit_provider, t.owner_org_unit_id,
               ou.name AS org_unit,
               (SELECT COUNT(*) FROM signoff s WHERE s.object_type='template' AND s.object_id=t.id) AS total_gates,
               (SELECT COUNT(*) FROM signoff s WHERE s.object_type='template' AND s.object_id=t.id AND s.decision='approved') AS approved_gates
        FROM template t LEFT JOIN org_unit ou ON ou.id=t.owner_org_unit_id
        WHERE t.status='draft'
        ORDER BY t.name
        """,
    )
    for request in template_requests:
        request["gates"] = rows(
            conn,
            "SELECT * FROM v_gate_status WHERE object_type='template' AND object_id=? ORDER BY sequence",
            (request["id"],),
        )
        for gate in request["gates"]:
            if gate["decision"] == "pending" and gate["is_next"]:
                gate["eligible_actors"] = eligible_actors(conn, gate["required_role"], None)
    changes = rows(
        conn,
        """
        SELECT cr.*, ci.product_name, p.display_name AS requested_by_name,
               (SELECT COUNT(*) FROM signoff s WHERE s.object_type='change' AND s.object_id=cr.id) AS total_gates,
               (SELECT COUNT(*) FROM signoff s WHERE s.object_type='change' AND s.object_id=cr.id AND s.decision='approved') AS approved_gates
        FROM change_request cr
        JOIN contract_instance ci ON ci.id=cr.instance_id
        JOIN person p ON p.id=cr.requested_by
        WHERE cr.status IN ('draft','in_review')
        ORDER BY cr.created_at
        """,
    )
    for request in changes:
        request["gates"] = rows(
            conn,
            "SELECT * FROM v_gate_status WHERE object_type='change' AND object_id=? ORDER BY sequence",
            (request["id"],),
        )
        for gate in request["gates"]:
            if gate["decision"] == "pending" and gate["is_next"]:
                gate["eligible_actors"] = eligible_actors(conn, gate["required_role"], None)
    return {"deployments": deployments, "templates": template_requests, "changes": changes}


def discovery(conn) -> dict:
    queue = rows(
        conn,
        "SELECT d.*, ch.name AS chain_name, ch.environment FROM discovery_queue d JOIN chain ch ON ch.id=d.chain_id ORDER BY d.first_seen_at DESC",
    )
    runs = rows(
        conn,
        """
        SELECT sr.*, ch.name AS chain_name FROM sync_run sr JOIN chain ch ON ch.id=sr.chain_id
        ORDER BY sr.started_at DESC
        """,
    )
    return {
        "queue": queue,
        "runs": runs,
        "chains": rows(conn, "SELECT * FROM v_chain_health ORDER BY chain_id"),
        "counts": {
            "new": sum(1 for q in queue if q["status"] == "new"),
            "triage": sum(1 for q in queue if q["status"] == "triage"),
            "quarantined": sum(1 for q in queue if q["status"] == "quarantined"),
            "linked": sum(1 for q in queue if q["status"] == "linked"),
        },
    }


def controls(conn) -> dict:
    return {
        "coverage": rows(conn, "SELECT * FROM v_control_coverage ORDER BY code"),
        "exceptions": rows(conn, "SELECT * FROM v_control_exceptions ORDER BY control_code"),
        "attestations": rows(conn, "SELECT * FROM v_attestation_alerts ORDER BY expires_at"),
        "incidents": rows(conn, "SELECT * FROM incident ORDER BY opened_at DESC"),
        "reserve": rows(conn, "SELECT * FROM v_token_reserve ORDER BY instance_id"),
        "readiness": rows(conn, "SELECT * FROM v_deployment_readiness ORDER BY id"),
        "chains": rows(conn, "SELECT * FROM v_chain_health ORDER BY chain_id"),
    }


def council(conn) -> dict:
    personas = rows(conn, "SELECT * FROM v_persona_summary ORDER BY sort_order")
    findings = rows(
        conn,
        "SELECT * FROM v_persona_findings ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END, created_at",
    )
    compliance = rows(conn, "SELECT * FROM v_compliance_coverage ORDER BY risk_tier DESC, product_name")
    ict = rows(conn, "SELECT * FROM v_ict_coverage ORDER BY criticality, provider")
    evidence_gaps = rows(conn, "SELECT * FROM v_signoff_evidence_gaps ORDER BY object_id, gate")
    template_gaps = rows(conn, "SELECT * FROM v_template_gate_gaps WHERE pending_gates > 0 OR gates = 0 ORDER BY id")
    deployer_risk = rows(conn, "SELECT * FROM v_deployer_risk ORDER BY risk_tier DESC, product_name")
    reserve = rows(conn, "SELECT * FROM v_reserve_reconciliation ORDER BY instance_id")
    return {
        "personas": personas,
        "findings": findings,
        "compliance": compliance,
        "ict": ict,
        "evidence_gaps": evidence_gaps,
        "template_gaps": template_gaps,
        "deployer_risk": deployer_risk,
        "reserve": reserve,
        "summary": {
            "open_findings": sum(1 for f in findings if f["status"] == "open"),
            "critical_high_open": sum(1 for f in findings if f["status"] == "open" and f["severity"] in ("critical", "high")),
            "risk_accepted": sum(1 for f in findings if f["status"] == "risk_accepted"),
            "remediated": sum(1 for f in findings if f["status"] in ("remediated", "closed")),
            "compliance_complete": sum(1 for c in compliance if c["status"] == "complete"),
            "compliance_partial": sum(1 for c in compliance if c["status"] == "partial"),
            "compliance_gap": sum(1 for c in compliance if c["status"] == "gap"),
            "evidence_gaps": len(evidence_gaps),
            "deployer_risks": len(deployer_risk),
            "ict_critical": sum(1 for i in ict if i["criticality"] == "critical"),
            "unreconciled_reserves": sum(
                1 for r in reserve
                if r["reserve_state"] == "current" and not r["bars_reconciled"] and r["counts_toward_reserve"] == 1
            ),
        },
    }


def registrations(conn) -> dict:
    items = rows(
        conn,
        """
        SELECT
            dr.id, dr.template_id, dr.chain_id, dr.environment, dr.product_name,
            dr.legal_entity, dr.jurisdiction, dr.risk_tier, dr.config_hash,
            dr.manifest_hash, dr.init_params_json, dr.salt, dr.status,
            dr.change_ticket, dr.target_window, dr.created_at, dr.approved_at, dr.notes,
            t.name AS template_name, t.version AS template_version,
            t.status AS template_status, t.runtime_code_hash AS template_runtime_hash,
            t.initcode_hash AS template_initcode_hash, t.audit_status, t.audit_valid_until,
            ch.name AS chain_name, ch.network_type, ch.environment AS chain_environment,
            req.display_name AS requested_by_name,
            owner.display_name AS business_owner_name,
            ou.name AS org_unit,
            r.readiness,
            (SELECT COUNT(*) FROM signoff s
              WHERE s.object_type='deployment' AND s.object_id=dr.id) AS total_gates,
            (SELECT COUNT(*) FROM signoff s
              WHERE s.object_type='deployment' AND s.object_id=dr.id AND s.decision='approved') AS approved_gates,
            (SELECT COUNT(*) FROM signoff s
              WHERE s.object_type='deployment' AND s.object_id=dr.id AND s.decision='pending') AS pending_gates,
            (SELECT COUNT(*) FROM contract_instance x
              WHERE x.deployment_request_id=dr.id) AS linked_records,
            (SELECT COUNT(*) FROM contract_instance x
              WHERE x.deployment_request_id=dr.id AND x.instance_kind='implementation') AS implementation_count,
            (SELECT COUNT(*) FROM contract_instance x
              WHERE x.deployment_request_id=dr.id AND x.instance_kind='supporting') AS supporting_count
        FROM deployment_request dr
        JOIN template t ON t.id = dr.template_id
        JOIN chain ch ON ch.id = dr.chain_id
        JOIN person req ON req.id = dr.requested_by
        JOIN person owner ON owner.id = dr.business_owner_id
        JOIN org_unit ou ON ou.id = dr.org_unit_id
        LEFT JOIN v_deployment_readiness r ON r.id = dr.id
        ORDER BY CASE dr.status
            WHEN 'in_review' THEN 1 WHEN 'approved' THEN 2
            WHEN 'deployed' THEN 3 ELSE 4 END, dr.created_at DESC
        """,
    )
    for item in items:
        instance = one(
            conn,
            """
            SELECT ci.*, ch.name AS chain_name
            FROM contract_instance ci
            JOIN chain ch ON ch.id = ci.chain_id
            WHERE ci.deployment_request_id = ? AND ci.instance_kind = 'logical'
            ORDER BY (ci.product_name = ?) DESC, ci.deployed_at DESC, ci.id
            LIMIT 1
            """,
            (item["id"], item["product_name"]),
        )
        item["instance_id"] = instance.get("id")
        item["address"] = instance.get("address")
        item["instance_address"] = instance.get("address")
        item["address_eip55"] = instance.get("address_eip55")
        item["deployment_tx"] = instance.get("deployment_tx")
        item["block_number"] = instance.get("block_number")
        item["deployed_at"] = instance.get("deployed_at")
        item["instance_runtime_hash"] = instance.get("runtime_code_hash")
        item["instance_initcode_hash"] = instance.get("init_code_hash")
        item["proxy_type"] = instance.get("proxy_type")
        item["implementation_address"] = instance.get("implementation_address")
        item["verification_status"] = instance.get("verification_status")
        item["verification_provider"] = instance.get("verification_provider")
        item["instance_status"] = instance.get("status")
        if not item.get("instance_id"):
            item["link_state"] = "pre_chain"
        elif (
            item.get("instance_runtime_hash")
            and item.get("template_runtime_hash")
            and item["instance_runtime_hash"].lower() == item["template_runtime_hash"].lower()
        ):
            item["link_state"] = "linked_match"
        else:
            item["link_state"] = "linked_mismatch"
        item["gates"] = rows(
            conn,
            "SELECT * FROM v_gate_status WHERE object_type='deployment' AND object_id=? ORDER BY sequence",
            (item["id"],),
        )
        item["manifest_document"] = one(
            conn,
            "SELECT * FROM document WHERE object_type='deployment_request' AND object_id=? AND doc_type='deployment_manifest' ORDER BY created_at DESC LIMIT 1",
            (item["id"],),
        )
    return {
        "items": items,
        "summary": {
            "total": len(items),
            "pre_chain": sum(1 for i in items if i["link_state"] == "pre_chain"),
            "linked": sum(1 for i in items if i["link_state"].startswith("linked")),
            "hash_matches": sum(1 for i in items if i["link_state"] == "linked_match"),
            "hash_mismatches": sum(1 for i in items if i["link_state"] == "linked_mismatch"),
            "in_review": sum(1 for i in items if i["status"] == "in_review"),
            "blocked": sum(1 for i in items if (i.get("readiness") or "").startswith("Blocked")),
        },
    }


def template_meta(conn) -> dict:
    return {
        "categories": rows(conn, "SELECT category, COUNT(*) AS count FROM template GROUP BY category ORDER BY count DESC"),
        "risk": rows(conn, "SELECT default_risk_tier AS risk_tier, COUNT(*) AS count FROM template GROUP BY default_risk_tier"),
    }


# ---------------------------------------------------------------------------
# Write actions (demo)
# ---------------------------------------------------------------------------


def decide_signoff(conn, signoff_id: str, payload: dict) -> tuple[int, dict]:
    decision = payload.get("decision")
    actor_id = payload.get("actor_id")
    comments = (payload.get("comments") or "").strip()
    if decision not in {"approved", "rejected"}:
        return 400, {"error": "decision must be approved or rejected"}
    if not actor_id:
        return 400, {"error": "actor_id is required"}

    s = conn.execute("SELECT * FROM signoff WHERE id = ?", (signoff_id,)).fetchone()
    if s is None:
        return 404, {"error": "signoff not found"}
    if s["decision"] != "pending":
        return 409, {"error": f"signoff is already {s['decision']}"}

    request_id = s["object_id"]
    object_type = s["object_type"]
    org_unit_id = None
    requested_by = None
    if object_type == "deployment":
        req = conn.execute("SELECT * FROM deployment_request WHERE id = ?", (request_id,)).fetchone()
        if req is None:
            return 404, {"error": "deployment request not found"}
        org_unit_id = req["org_unit_id"]
        requested_by = req["requested_by"]
    elif object_type == "change":
        req = conn.execute("SELECT * FROM change_request WHERE id = ?", (request_id,)).fetchone()
        if req is None:
            return 404, {"error": "change request not found"}
        requested_by = req["requested_by"]
    elif object_type == "template":
        req = conn.execute("SELECT * FROM template WHERE id = ?", (request_id,)).fetchone()
        if req is None:
            return 404, {"error": "template not found"}
    else:
        return 400, {"error": "unsupported object type"}

    if not person_has_role(conn, actor_id, s["required_role"], org_unit_id):
        return 403, {"error": f"{actor_id} does not hold an active {s['required_role']} role for this scope"}
    if decision == "approved" and requested_by and actor_id == requested_by:
        return 409, {"error": "segregation of duties: the requester cannot approve this request"}
    if decision == "approved":
        prior = conn.execute(
            """
            SELECT gate FROM signoff
            WHERE object_type = ? AND object_id = ? AND decided_by = ?
              AND decision = 'approved' AND id <> ?
            LIMIT 1
            """,
            (object_type, request_id, actor_id, signoff_id),
        ).fetchone()
        if prior:
            return 409, {
                "error": f"four-eyes: {actor_id} already approved the {prior['gate']} gate on this object"
            }

    earlier = conn.execute(
        """
        SELECT gs.gate, gs.sequence
        FROM v_gate_status gs
        WHERE gs.object_type = ? AND gs.object_id = ? AND gs.blocking = 1
          AND gs.sequence < (SELECT sequence FROM v_gate_status WHERE id = ?)
          AND gs.decision <> 'approved'
        ORDER BY gs.sequence
        """,
        (object_type, request_id, signoff_id),
    ).fetchall()
    if decision == "approved" and earlier:
        names = ", ".join(r["gate"] for r in earlier)
        return 409, {"error": f"previous blocking gate(s) not approved: {names}"}

    before = dict(s)
    conn.execute(
        """
        UPDATE signoff
        SET decision = ?, decided_by = ?, decided_at = ?, comments = ?,
            evidence_uri = COALESCE(?, evidence_uri),
            auth_method = 'demo-actor-selector'
        WHERE id = ?
        """,
        (decision, actor_id, utcnow(), comments, payload.get("evidence_uri"), signoff_id),
    )
    after = dict(conn.execute("SELECT * FROM signoff WHERE id = ?", (signoff_id,)).fetchone())
    conn.execute(
        """
        INSERT INTO audit_log (actor, actor_type, action, object_type, object_id,
                               before_json, after_json, at, correlation_id)
        VALUES (?, 'person', 'signoff.updated', 'signoff', ?, ?, ?, ?, ?)
        """,
        (
            actor_id,
            signoff_id,
            json.dumps({"decision": before["decision"]}),
            json.dumps({"decision": after["decision"], "comments": comments}),
            utcnow(),
            "ui-" + signoff_id,
        ),
    )

    if object_type in {"deployment", "change", "template"}:
        table = {
            "deployment": "deployment_request",
            "change": "change_request",
            "template": "template",
        }[object_type]
        pending = scalar(
            conn,
            "SELECT COUNT(*) FROM signoff WHERE object_type = ? AND object_id = ? AND decision = 'pending'",
            (object_type, request_id),
        )
        rejected = scalar(
            conn,
            "SELECT COUNT(*) FROM signoff WHERE object_type = ? AND object_id = ? AND decision = 'rejected'",
            (object_type, request_id),
        )
        if rejected:
            if object_type == "template":
                conn.execute("UPDATE template SET status = 'blocked' WHERE id = ?", (request_id,))
            else:
                conn.execute(f"UPDATE {table} SET status = 'rejected' WHERE id = ?", (request_id,))
        elif pending == 0 and decision == "approved":
            if object_type == "deployment":
                readiness = conn.execute(
                    "SELECT readiness FROM v_deployment_readiness WHERE id = ?", (request_id,)
                ).fetchone()
                if readiness and not readiness["readiness"].startswith("Ready"):
                    conn.rollback()
                    return 409, {"error": f"cannot complete approval: {readiness['readiness']}"}
            if object_type == "template":
                template = conn.execute(
                    "SELECT audit_status, audit_valid_until FROM template WHERE id = ?", (request_id,)
                ).fetchone()
                audit_ok = (
                    template
                    and template["audit_status"] in ("external", "internal")
                    and template["audit_valid_until"]
                    and template["audit_valid_until"] >= utcnow()[:10]
                )
                if not audit_ok:
                    conn.rollback()
                    return 409, {"error": "cannot approve template: independent audit is missing or expired"}
            conn.execute(
                f"UPDATE {table} SET status = 'approved', approved_at = ? WHERE id = ?",
                (utcnow(), request_id),
            )
    conn.commit()
    return 200, {
        "ok": True,
        "signoff_id": signoff_id,
        "decision": decision,
        "object_type": object_type,
        "object_id": request_id,
        "message": f"{s['gate']} gate {decision}",
    }


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------


class Handler(BaseHTTPRequestHandler):
    server_version = "SCRDemo/0.2"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path):
        if not path.exists() or not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        content_type, _ = mimetypes.guess_type(str(path))
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_web(self, relative: str):
        root = WEB_ROOT.resolve()
        target = (WEB_ROOT / relative).resolve()
        if target != root and root not in target.parents:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self._send_file(target)

    def do_GET(self):
        parsed = urlparse(self.path)
        route = parsed.path
        query = {k: v[-1] for k, v in parse_qs(parsed.query).items()}
        if route == "/":
            return self._send_web("index.html")
        if route.startswith("/static/"):
            return self._send_web(route.removeprefix("/static/"))
        if not route.startswith("/api/"):
            return self._send_web(route.lstrip("/"))

        conn = self.server.db.connect()
        try:
            if route == "/api/health":
                return self._send_json(200, {"ok": True, "db": str(self.server.db.path), "time": utcnow()})
            if route == "/api/summary":
                return self._send_json(200, summary(conn))
            if route == "/api/contracts":
                return self._send_json(200, {"items": inventory(conn, query)})
            if route.startswith("/api/contracts/"):
                detail = instance_detail(conn, route.removeprefix("/api/contracts/"))
                return self._send_json(200, detail) if detail else self._send_json(404, {"error": "not found"})
            if route == "/api/templates":
                return self._send_json(200, {"items": templates(conn), "meta": template_meta(conn)})
            if route.startswith("/api/templates/"):
                detail = template_detail(conn, route.removeprefix("/api/templates/"))
                return self._send_json(200, detail) if detail else self._send_json(404, {"error": "not found"})
            if route == "/api/approvals":
                return self._send_json(200, approvals(conn))
            if route == "/api/registrations":
                return self._send_json(200, registrations(conn))
            if route == "/api/discovery":
                return self._send_json(200, discovery(conn))
            if route == "/api/controls":
                return self._send_json(200, controls(conn))
            if route == "/api/council":
                return self._send_json(200, council(conn))
            if route == "/api/audit":
                return self._send_json(200, {"items": rows(conn, "SELECT * FROM audit_log ORDER BY at DESC LIMIT 100")})
            return self._send_json(404, {"error": "unknown endpoint"})
        except Exception as exc:
            return self._send_json(500, {"error": str(exc)})
        finally:
            conn.close()

    def do_POST(self):
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            return self._send_json(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            return self._send_json(400, {"error": "invalid JSON"})

        conn = self.server.db.connect()
        try:
            parts = parsed.path.strip("/").split("/")
            if len(parts) == 4 and parts[0] == "api" and parts[1] == "signoffs" and parts[3] == "decision":
                status, body = decide_signoff(conn, parts[2], payload)
                return self._send_json(status, body)
            if len(parts) == 2 and parts[0] == "api" and parts[1] == "sync":
                chain_id = payload.get("chain_id", "ch-besu-prod")
                return self._send_json(200, run_mock(self.server.db.path, chain_id))
            return self._send_json(404, {"error": "unknown endpoint"})
        except sqlite3.IntegrityError as exc:
            conn.rollback()
            return self._send_json(409, {"error": str(exc)})
        except Exception as exc:
            conn.rollback()
            return self._send_json(500, {"error": str(exc)})
        finally:
            conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB_PATH)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    if not args.db.exists():
        raise SystemExit(f"database not found: {args.db}; run scripts/build_db.py first")
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.db = RegistryDB(args.db)
    print(f"Smart Contract Registry demo: http://{args.host}:{args.port}")
    print("Local demo only — no authentication or TLS.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
