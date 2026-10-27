#!/usr/bin/env python3
"""Behavioural tests for the SQLite registry demo."""

from __future__ import annotations

import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "registry"))

from build_db import build  # noqa: E402


class RegistryTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory()
        cls.db_path = Path(cls.tempdir.name) / "registry.db"
        build(cls.db_path)
        cls.conn = sqlite3.connect(cls.db_path)
        cls.conn.row_factory = sqlite3.Row
        cls.conn.execute("PRAGMA foreign_keys = ON")

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()
        cls.tempdir.cleanup()

    def one(self, sql, params=()):
        return self.conn.execute(sql, params).fetchone()

    def all(self, sql, params=()):
        return self.conn.execute(sql, params).fetchall()

    def test_schema_is_integrity_clean(self):
        self.assertEqual(self.one("PRAGMA integrity_check")[0], "ok")
        self.assertEqual(self.all("PRAGMA foreign_key_check"), [])

    def test_template_to_deployment_linkage(self):
        rows = self.all(
            """
            SELECT ci.id, ci.chain_id, t.template_key
            FROM contract_instance ci
            JOIN template t ON t.id = ci.template_id
            WHERE ci.instance_kind = 'logical'
            """
        )
        self.assertEqual(len(rows), 16)
        self.assertTrue(all(r["chain_id"] and r["template_key"] for r in rows))

        cmtat = self.one(
            """
            SELECT COUNT(*) AS n, COUNT(DISTINCT chain_id) AS chains
            FROM contract_instance
            WHERE template_id = 'tpl-cmtat-300' AND instance_kind = 'logical'
            """
        )
        self.assertEqual(cmtat["n"], 3)
        self.assertEqual(cmtat["chains"], 2)

        orphans = self.one(
            """
            SELECT COUNT(*) AS n
            FROM contract_instance ci
            LEFT JOIN template t ON t.id = ci.template_id
            WHERE t.id IS NULL
            """
        )
        self.assertEqual(orphans["n"], 0)

    def test_every_logical_instance_has_owner_and_risk(self):
        rows = self.all(
            """
            SELECT id FROM contract_instance
            WHERE instance_kind = 'logical'
              AND (business_owner_id IS NULL OR org_unit_id IS NULL OR risk_tier IS NULL)
            """
        )
        self.assertEqual(rows, [])

    def test_public_token_proxy_binding(self):
        row = self.one(
            """
            SELECT proxy_type, implementation_address, admin_address
            FROM contract_instance WHERE id = 'ci-ubgx-eth'
            """
        )
        self.assertEqual(row["proxy_type"], "eip1967-uups")
        self.assertEqual(row["implementation_address"], "0xf70be54517e4f2c31a25be1432572c56b77024a3")
        link = self.one(
            """
            SELECT relation FROM contract_link
            WHERE from_instance_id = 'ci-ubgx-eth'
              AND to_instance_id = 'ci-ubgx-eth-impl'
            """
        )
        self.assertEqual(link["relation"], "delegates_to")

    def test_reserve_coverage_and_no_double_count(self):
        rows = self.all(
            """
            SELECT instance_id, total_supply, gold_grams, coverage_ratio, counts_toward_reserve
            FROM v_token_reserve WHERE reserve_state = 'current'
            """
        )
        by_id = {r["instance_id"]: r for r in rows}
        self.assertAlmostEqual(by_id["ci-ubgx-eth"]["coverage_ratio"], 1.01)
        self.assertAlmostEqual(by_id["ci-ubgx-besu"]["coverage_ratio"], 1.01)
        self.assertEqual(by_id["ci-ubgx-besu-uat"]["counts_toward_reserve"], 0)

        total = self.one(
            """
            SELECT SUM(total_supply) AS supply
            FROM token_metadata
            WHERE underlying_asset = 'XAU' AND counts_toward_reserve = 1
            """
        )
        self.assertAlmostEqual(total["supply"], 125000.0)

    def test_readiness_gate_blocks_unaudited_template(self):
        row = self.one(
            "SELECT readiness, pending_blocking_gates FROM v_deployment_readiness WHERE id = 'DR-2026-0060'"
        )
        self.assertTrue(row["readiness"].startswith("Blocked"))
        self.assertGreater(row["pending_blocking_gates"], 0)

        row = self.one(
            "SELECT readiness FROM v_deployment_readiness WHERE id = 'DR-2026-0051'"
        )
        self.assertTrue(row["readiness"].startswith("In review"))

        row = self.one(
            "SELECT readiness FROM v_deployment_readiness WHERE id = 'DR-2026-0031'"
        )
        self.assertEqual(row["readiness"], "Ready")

    def test_next_gate_sequence(self):
        rows = self.all(
            """
            SELECT gate, sequence, is_next
            FROM v_gate_status
            WHERE object_type = 'deployment' AND object_id = 'DR-2026-0051'
            ORDER BY sequence
            """
        )
        self.assertEqual(rows[0]["gate"], "BUSINESS")
        self.assertEqual(rows[0]["is_next"], 0)
        self.assertEqual(rows[3]["gate"], "LEGAL")
        self.assertEqual(rows[3]["is_next"], 1)

    def test_segregation_of_duties_trigger(self):
        self.conn.execute(
            """
            INSERT INTO deployment_request
              (id, template_id, chain_id, environment, requested_by, business_owner_id,
               org_unit_id, product_name, legal_entity, jurisdiction, risk_tier,
               config_hash, status, created_at)
            VALUES
              ('DR-TEST-SOD', 'tpl-cmtat-300', 'ch-besu-prod', 'PROD', 'p-elena',
               'p-elena', 'org-gwm-com', 'SoD test', 'Financial Institution AG', 'CH', 'low',
               '0x' || printf('%064d', 0), 'in_review', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
            VALUES ('so-test-sod', 'deployment', 'DR-TEST-SOD', 'BUSINESS', 'Business Owner',
                    'pending', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.commit()
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            self.conn.execute(
                """
                UPDATE signoff
                SET decision = 'approved', decided_by = 'p-elena',
                    decided_at = '2026-10-26T01:00:00Z'
                WHERE id = 'so-test-sod'
                """
            )
        self.assertIn("SoD", str(ctx.exception))
        self.conn.rollback()

    def test_role_eligibility_trigger(self):
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            self.conn.execute(
                """
                UPDATE signoff
                SET decision = 'approved', decided_by = 'p-claudia',
                    decided_at = '2026-10-26T01:00:00Z'
                WHERE object_type = 'deployment'
                  AND object_id = 'DR-2026-0063'
                  AND gate = 'RISK'
                """
            )
        self.assertIn("role", str(ctx.exception).lower())
        self.conn.rollback()

    def test_duplicate_chain_address_rejected(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.conn.execute(
                """
                INSERT INTO contract_instance
                  (id, chain_id, address, template_id, runtime_code_hash, status, risk_tier,
                   verification_status)
                VALUES
                  ('ci-duplicate', 'ch-besu-prod',
                   '0x46009f357c42ca5895de915a469cbb56b760411e',
                   'tpl-cmtat-300', '0xdeadbeef', 'active', 'high', 'unverified')
                """
            )
        self.conn.rollback()

    def test_unknown_contracts_are_visible(self):
        rows = self.all("SELECT id, status FROM v_unlinked_discoveries ORDER BY id")
        self.assertEqual([r["id"] for r in rows], ["disc-001", "disc-002", "disc-003"])
        self.assertEqual(rows[2]["status"], "quarantined")

    def test_attestation_alerts(self):
        rows = self.all("SELECT id, alert_level FROM v_attestation_alerts ORDER BY id")
        levels = {r["id"]: r["alert_level"] for r in rows}
        self.assertEqual(levels["att-cmtat320-self"], "expired")
        self.assertEqual(levels["att-por-eth"], "critical")

    def test_control_exceptions_are_traceable(self):
        rows = self.all(
            """
            SELECT instance_id, control_code, status
            FROM v_control_exceptions
            WHERE instance_id IN ('ci-rule-country', 'ci-dvp-gold')
            """
        )
        self.assertGreaterEqual(len(rows), 3)
        self.assertTrue(any(r["control_code"] == "SC-05" for r in rows))
        self.assertTrue(any(r["control_code"] == "SC-04" for r in rows))

    def test_signoff_evidence_is_complete_for_approved_requests(self):
        rows = self.all(
            """
            SELECT dr.id, COUNT(s.id) AS gates,
                   SUM(CASE WHEN s.decision = 'approved' THEN 1 ELSE 0 END) AS approved
            FROM deployment_request dr
            JOIN signoff s ON s.object_type = 'deployment' AND s.object_id = dr.id
            WHERE dr.status IN ('approved', 'deployed')
            GROUP BY dr.id
            """
        )
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(row["gates"], row["approved"], row["id"])

    def test_clone_and_dependency_graph(self):
        row = self.one(
            """
            SELECT COUNT(*) AS n FROM contract_link
            WHERE from_instance_id = 'ci-ubgx-besu'
              AND relation IN ('uses_rule_engine', 'uses_identity_registry', 'prices_from', 'attested_by')
            """
        )
        self.assertEqual(row["n"], 4)
        row = self.one(
            """
            SELECT COUNT(*) AS n FROM contract_link
            WHERE relation = 'deployed_by_factory'
            """
        )
        self.assertEqual(row["n"], 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)


class ApiActionsTestCase(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tempdir.name) / "registry.db"
        build(self.db_path)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        sys.path.insert(0, str(ROOT))
        from app import decide_signoff  # noqa: PLC0415
        self.decide = decide_signoff

    def tearDown(self):
        self.conn.close()
        self.tempdir.cleanup()

    def test_wrong_role_is_rejected_by_api(self):
        status, body = self.decide(
            self.conn,
            "so-dr-2026-0051-legal",
            {"decision": "approved", "actor_id": "p-claudia"},
        )
        self.assertEqual(status, 403)
        self.assertIn("role", body["error"])

    def test_eligible_legal_approval_succeeds(self):
        status, body = self.decide(
            self.conn,
            "so-dr-2026-0051-legal",
            {"decision": "approved", "actor_id": "p-daniel", "comments": "Legal opinion reviewed."},
        )
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        row = self.conn.execute(
            "SELECT decision, decided_by FROM signoff WHERE id='so-dr-2026-0051-legal'"
        ).fetchone()
        self.assertEqual(row["decision"], "approved")
        self.assertEqual(row["decided_by"], "p-daniel")

    def test_final_gate_cannot_bypass_blocked_template(self):
        self.conn.execute(
            """
            INSERT INTO deployment_request
              (id, template_id, chain_id, environment, requested_by, business_owner_id,
               org_unit_id, product_name, legal_entity, jurisdiction, risk_tier,
               config_hash, status, created_at)
            VALUES
              ('DR-TEST-BLOCK', 'tpl-cmtat-320', 'ch-eth-mainnet', 'PROD', 'p-priya',
               'p-elena', 'org-gwm-com', 'Blocked test', 'Financial Institution AG', 'CH', 'high',
               '0x' || printf('%064d', 0), 'in_review', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
            VALUES ('so-test-block-cab', 'deployment', 'DR-TEST-BLOCK', 'CAB',
                    'Change Advisory Board', 'pending', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.commit()
        status, body = self.decide(
            self.conn,
            "so-test-block-cab",
            {"decision": "approved", "actor_id": "p-reto", "comments": "CAB test"},
        )
        self.assertEqual(status, 409)
        self.assertIn("cannot complete approval", body["error"])

    def test_mock_sync_is_idempotent(self):
        from besu_sync import run_mock  # noqa: PLC0415
        first = run_mock(self.db_path, "ch-besu-prod")
        second = run_mock(self.db_path, "ch-besu-prod")
        self.assertEqual(first["address"], second["address"])
        count = self.conn.execute(
            "SELECT COUNT(*) FROM discovery_queue WHERE chain_id='ch-besu-prod' AND address=?",
            (first["address"],),
        ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_template_final_approval_requires_independent_audit(self):
        self.conn.execute(
            """
            UPDATE signoff SET decision='approved', decided_by='p-lucas', decided_at='2026-10-26T00:00:00Z'
            WHERE id='so-tpl-cmtat-320-security'
            """
        )
        self.conn.execute(
            """
            UPDATE signoff SET decision='approved', decided_by='p-andrea', decided_at='2026-10-26T00:00:00Z'
            WHERE id='so-tpl-cmtat-320-audit_evidence'
            """
        )
        self.conn.execute(
            """
            UPDATE signoff SET decision='approved', decided_by='p-daniel', decided_at='2026-10-26T00:00:00Z'
            WHERE id='so-tpl-cmtat-320-legal'
            """
        )
        self.conn.commit()
        status, body = self.decide(
            self.conn,
            "so-tpl-cmtat-320-sourcing",
            {"decision": "approved", "actor_id": "p-nina", "comments": "Final template gate"},
        )
        self.assertEqual(status, 409)
        self.assertIn("independent audit", body["error"])

    def test_reserve_bars_reconcile_for_production_pools(self):
        rows = self.conn.execute(
            """
            SELECT instance_id, supply_delta, bar_delta, bars_reconciled
            FROM v_reserve_reconciliation
            WHERE counts_toward_reserve = 1 AND reserve_state = 'current'
            """
        ).fetchall()
        self.assertGreaterEqual(len(rows), 2)
        for row in rows:
            self.assertEqual(row["supply_delta"], 0, row["instance_id"])
            self.assertEqual(row["bar_delta"], 0, row["instance_id"])
            self.assertEqual(row["bars_reconciled"], 1, row["instance_id"])

    def test_high_critical_templates_have_complete_gates(self):
        rows = self.conn.execute("SELECT id, gates, pending_gates FROM v_template_gate_gaps").fetchall()
        self.assertGreater(len(rows), 10)
        for row in rows:
            self.assertGreater(row["gates"], 0, row["id"])
            self.assertEqual(row["pending_gates"], 0, row["id"])

    def test_duplicate_approver_trigger(self):
        self.conn.execute(
            """
            INSERT INTO deployment_request
              (id, template_id, chain_id, environment, requested_by, business_owner_id,
               org_unit_id, product_name, legal_entity, jurisdiction, risk_tier,
               config_hash, status, created_at)
            VALUES
              ('DR-TEST-4EYES', 'tpl-cmtat-300', 'ch-besu-prod', 'PROD', 'p-priya',
               'p-elena', 'org-gwm-com', 'Four eyes test', 'Financial Institution AG', 'CH', 'high',
               '0x' || printf('%064d', 0), 'in_review', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
            VALUES ('so-test-4eyes-business', 'deployment', 'DR-TEST-4EYES', 'BUSINESS',
                    'Business Owner', 'pending', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
            VALUES ('so-test-4eyes-product', 'deployment', 'DR-TEST-4EYES', 'PRODUCT',
                    'Product Owner', 'pending', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            UPDATE signoff SET decision='approved', decided_by='p-marco',
                decided_at='2026-10-26T01:00:00Z'
            WHERE id='so-test-4eyes-business'
            """
        )
        self.conn.commit()
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            self.conn.execute(
                """
                UPDATE signoff SET decision='approved', decided_by='p-marco',
                    decided_at='2026-10-26T02:00:00Z'
                WHERE id='so-test-4eyes-product'
                """
            )
        self.assertIn("Four-eyes", str(ctx.exception))
        self.conn.rollback()

    def test_audit_log_is_append_only(self):
        row = self.conn.execute("SELECT id FROM audit_log LIMIT 1").fetchone()
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            self.conn.execute("UPDATE audit_log SET action='tampered' WHERE id=?", (row["id"],))
        self.assertIn("append-only", str(ctx.exception))
        self.conn.rollback()

    def test_persona_council_and_compliance_profiles(self):
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM persona").fetchone()[0], 8)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM persona_finding").fetchone()[0], 20)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM compliance_profile").fetchone()[0], 7)
        open_high = self.conn.execute(
            "SELECT COUNT(*) FROM persona_finding WHERE status='open' AND severity IN ('critical','high')"
        ).fetchone()[0]
        self.assertGreater(open_high, 0)
        row = self.conn.execute(
            "SELECT status, dora_register_ref FROM v_compliance_coverage WHERE instance_id='ci-ubgx-eth'"
        ).fetchone()
        self.assertEqual(row["status"], "partial")
        self.assertEqual(row["dora_register_ref"], "DORA-GOLD-001")

    def test_evidence_gaps_are_explicit(self):
        rows = self.conn.execute("SELECT COUNT(*) FROM v_signoff_evidence_gaps").fetchone()[0]
        self.assertGreater(rows, 0)
        # The view must only contain approved decisions, never pending ones.
        bad = self.conn.execute(
            "SELECT COUNT(*) FROM v_signoff_evidence_gaps WHERE decision <> 'approved'"
        ).fetchone()[0]
        self.assertEqual(bad, 0)

    def test_deployer_risk_flags_legacy_eoa(self):
        row = self.conn.execute(
            "SELECT signing_identity, allowlisted FROM v_deployer_risk WHERE id='ci-ubgx-besu-v2'"
        ).fetchone()
        self.assertEqual(row["signing_identity"], "Legacy Besu deployer")
        self.assertEqual(row["allowlisted"], 0)
        good = self.conn.execute(
            "SELECT allowlisted FROM v_deployer_risk WHERE id='ci-ubgx-eth'"
        ).fetchone()
        self.assertIsNone(good)  # allowlisted instances are excluded from the risk view

    def test_api_four_eyes_rejects_second_gate(self):
        self.conn.execute(
            """
            INSERT INTO deployment_request
              (id, template_id, chain_id, environment, requested_by, business_owner_id,
               org_unit_id, product_name, legal_entity, jurisdiction, risk_tier,
               config_hash, status, created_at)
            VALUES
              ('DR-TEST-API-4EYES', 'tpl-cmtat-300', 'ch-besu-prod', 'PROD', 'p-priya',
               'p-marco', 'org-gwm-da', 'API four eyes test', 'Financial Institution AG', 'CH', 'high',
               '0x' || printf('%064d', 0), 'in_review', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
            VALUES ('so-test-api-4eyes-business', 'deployment', 'DR-TEST-API-4EYES',
                    'BUSINESS', 'Business Owner', 'pending', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
            VALUES ('so-test-api-4eyes-product', 'deployment', 'DR-TEST-API-4EYES',
                    'PRODUCT', 'Product Owner', 'pending', '2026-10-26T00:00:00Z')
            """
        )
        self.conn.execute(
            """
            UPDATE signoff SET decision='approved', decided_by='p-marco',
                decided_at='2026-10-26T01:00:00Z'
            WHERE id='so-test-api-4eyes-business'
            """
        )
        self.conn.commit()
        status, body = self.decide(
            self.conn,
            "so-test-api-4eyes-product",
            {"decision": "approved", "actor_id": "p-marco", "comments": "second gate"},
        )
        self.assertEqual(status, 409)
        self.assertIn("four-eyes", body["error"].lower())

    def test_registration_links_prechain_request_to_instance(self):
        from app import registrations  # noqa: PLC0415
        data = registrations(self.conn)
        by_id = {item["id"]: item for item in data["items"]}
        self.assertEqual(by_id["DR-2026-0031"]["instance_id"], "ci-ubgx-eth")
        self.assertEqual(by_id["DR-2026-0031"]["link_state"], "linked_match")
        self.assertEqual(by_id["DR-2026-0042"]["instance_id"], "ci-ubgx-besu")
        self.assertEqual(by_id["DR-2026-0051"]["instance_id"], None)
        self.assertEqual(by_id["DR-2026-0051"]["link_state"], "pre_chain")
        self.assertEqual(data["summary"]["pre_chain"], 3)
        self.assertEqual(data["summary"]["linked"], 4)
