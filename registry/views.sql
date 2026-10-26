-- Read models used by the API and UI.

CREATE VIEW v_inventory AS
SELECT
    ci.id,
    ci.chain_id,
    ch.name                         AS chain_name,
    ch.network_type,
    ch.environment,
    ci.address,
    ci.instance_kind,
    ci.representation,
    ci.status,
    ci.risk_tier,
    ci.criticality,
    ci.business_owner_id,
    owner.display_name              AS business_owner,
    ci.org_unit_id,
    ou.name                         AS org_unit,
    ou.division,
    ci.legal_entity,
    ci.jurisdiction,
    ci.product_name,
    ci.classification,
    t.id                            AS template_id,
    t.name                          AS template_name,
    t.template_key,
    t.version                       AS template_version,
    t.category,
    t.contract_type,
    t.audit_status,
    t.audit_provider,
    t.audit_valid_until,
    CASE
        WHEN t.audit_status = 'none' THEN 'none'
        WHEN t.audit_status = 'self' THEN 'self-assessed'
        WHEN t.audit_valid_until IS NULL THEN 'unknown'
        WHEN date(t.audit_valid_until) < date('now') THEN 'expired'
        WHEN date(t.audit_valid_until) <= date('now', '+60 days') THEN 'expiring'
        ELSE 'valid'
    END                             AS template_audit_state,
    CAST(julianday(t.audit_valid_until) - julianday('now') AS INTEGER) AS audit_days_left,
    ci.verification_status,
    ci.verification_provider,
    ci.verification_url,
    ci.deployed_at,
    ci.block_number,
    ci.deployment_tx,
    ci.proxy_type,
    ci.implementation_address,
    ci.admin_address,
    ci.privacy_group,
    ci.is_canonical,
    ci.supersedes_id,
    (SELECT COUNT(*) FROM contract_link l WHERE l.from_instance_id = ci.id) AS dependency_count,
    (SELECT COUNT(*) FROM attestation a WHERE a.instance_id = ci.id AND a.status = 'valid') AS valid_attestations,
    (SELECT COUNT(*) FROM signoff s WHERE s.object_type = 'instance' AND s.object_id = ci.id AND s.decision = 'pending') AS pending_instance_gates,
    si.name AS signer_identity,
    si.key_type AS signer_key_type,
    si.allowlisted AS signer_allowlisted,
    cp.status AS compliance_status,
    cp.aml_risk_rating
FROM contract_instance ci
JOIN chain ch ON ch.id = ci.chain_id
JOIN template t ON t.id = ci.template_id
LEFT JOIN person owner ON owner.id = ci.business_owner_id
LEFT JOIN org_unit ou ON ou.id = ci.org_unit_id
LEFT JOIN signing_identity si ON si.id = ci.signing_identity_id
LEFT JOIN compliance_profile cp ON cp.instance_id = ci.id
WHERE ci.instance_kind = 'logical';

CREATE VIEW v_template_usage AS
SELECT
    t.*,
    COUNT(ci.id) AS deployments,
    COUNT(DISTINCT ci.chain_id) AS chains_used,
    MAX(ci.deployed_at) AS last_deployed_at,
    GROUP_CONCAT(DISTINCT CASE WHEN ci.id IS NOT NULL THEN ch.name END) AS chain_names,
    SUM(CASE WHEN ci.status IN ('active', 'paused', 'deployed') THEN 1 ELSE 0 END) AS live_instances,
    CASE
        WHEN t.audit_status = 'none' THEN 'none'
        WHEN t.audit_status = 'self' THEN 'self-assessed'
        WHEN t.audit_valid_until IS NULL THEN 'unknown'
        WHEN date(t.audit_valid_until) < date('now') THEN 'expired'
        WHEN date(t.audit_valid_until) <= date('now', '+60 days') THEN 'expiring'
        ELSE 'valid'
    END AS audit_state
FROM template t
LEFT JOIN contract_instance ci ON ci.template_id = t.id
LEFT JOIN chain ch ON ch.id = ci.chain_id
GROUP BY t.id;

CREATE VIEW v_gate_status AS
WITH object_risk AS (
    SELECT 'deployment' AS object_type, id AS object_id, risk_tier FROM deployment_request
    UNION ALL
    SELECT 'change', id, risk_tier FROM change_request
    UNION ALL
    SELECT 'template', id, default_risk_tier FROM template
)
SELECT
    s.id,
    s.object_type,
    s.object_id,
    s.gate,
    s.required_role,
    s.decision,
    s.decided_by,
    p.display_name AS decided_by_name,
    s.decided_at,
    s.comments,
    s.evidence_uri,
    s.evidence_hash,
    s.document_id,
    s.auth_method,
    s.expires_at,
    s.created_at,
    pol.sequence,
    pol.blocking,
    r.risk_tier,
    CASE
        WHEN s.decision = 'pending' AND NOT EXISTS (
            SELECT 1
            FROM signoff prev
            JOIN approval_policy pp
              ON pp.object_type = prev.object_type
             AND pp.risk_tier = r.risk_tier
             AND pp.gate = prev.gate
             AND pp.required_role = prev.required_role
            WHERE prev.object_type = s.object_type
              AND prev.object_id = s.object_id
              AND prev.decision <> 'approved'
              AND pp.blocking = 1
              AND pp.sequence < pol.sequence
        ) THEN 1 ELSE 0
    END AS is_next,
    (
        SELECT COUNT(DISTINCT ra.person_id)
        FROM role_assignment ra
        JOIN person pe ON pe.id = ra.person_id AND pe.active = 1
        WHERE ra.role_code = s.required_role
          AND ra.active = 1
    ) AS eligible_actor_count
FROM signoff s
JOIN object_risk r ON r.object_type = s.object_type AND r.object_id = s.object_id
JOIN approval_policy pol
  ON pol.object_type = s.object_type
 AND pol.risk_tier = r.risk_tier
 AND pol.gate = s.gate
 AND pol.required_role = s.required_role
LEFT JOIN person p ON p.id = s.decided_by;

CREATE VIEW v_deployment_readiness AS
SELECT
    dr.id,
    dr.status AS request_status,
    t.status AS template_status,
    t.audit_status,
    t.audit_valid_until,
    CASE WHEN date(t.audit_valid_until) < date('now') THEN 1 ELSE 0 END AS audit_expired,
    (
        SELECT COUNT(*)
        FROM signoff s
        JOIN approval_policy p
          ON p.object_type = s.object_type
         AND p.risk_tier = dr.risk_tier
         AND p.gate = s.gate
         AND p.required_role = s.required_role
        WHERE s.object_type = 'deployment'
          AND s.object_id = dr.id
          AND s.decision = 'pending'
          AND p.blocking = 1
    ) AS pending_blocking_gates,
    EXISTS (
        SELECT 1 FROM signoff s
        WHERE s.object_type = 'deployment' AND s.object_id = dr.id AND s.decision = 'rejected'
    ) AS has_rejection,
    CASE
        WHEN t.status <> 'approved' THEN 'Blocked: template not approved'
        WHEN t.default_risk_tier IN ('high', 'critical') AND EXISTS (
            SELECT 1 FROM signoff ts
            WHERE ts.object_type = 'template' AND ts.object_id = t.id AND ts.decision = 'pending'
        ) THEN 'Blocked: template approval incomplete'
        WHEN t.audit_status NOT IN ('external', 'internal') THEN 'Blocked: independent audit missing'
        WHEN t.audit_valid_until IS NULL OR date(t.audit_valid_until) < date('now') THEN 'Blocked: audit expired'
        WHEN EXISTS (
            SELECT 1 FROM signoff s
            WHERE s.object_type = 'deployment' AND s.object_id = dr.id AND s.decision = 'rejected'
        ) THEN 'Blocked: approval rejected'
        WHEN (
            SELECT COUNT(*)
            FROM signoff s
            JOIN approval_policy p
              ON p.object_type = s.object_type
             AND p.risk_tier = dr.risk_tier
             AND p.gate = s.gate
             AND p.required_role = s.required_role
            WHERE s.object_type = 'deployment'
              AND s.object_id = dr.id
              AND s.decision = 'pending'
              AND p.blocking = 1
        ) > 0 THEN 'In review: approvals incomplete'
        ELSE 'Ready'
    END AS readiness
FROM deployment_request dr
JOIN template t ON t.id = dr.template_id;

CREATE VIEW v_pending_approvals AS
SELECT
    dr.id,
    dr.status,
    dr.risk_tier,
    dr.product_name,
    dr.environment,
    dr.config_hash,
    dr.change_ticket,
    dr.target_window,
    dr.created_at,
    dr.approved_at,
    t.id AS template_id,
    t.name AS template_name,
    t.version AS template_version,
    t.audit_status,
    t.audit_valid_until,
    ch.name AS chain_name,
    ch.network_type,
    ch.environment AS chain_environment,
    req.display_name AS requested_by_name,
    owner.display_name AS business_owner_name,
    dr.org_unit_id,
    ou.name AS org_unit,
    r.readiness,
    r.pending_blocking_gates,
    (SELECT COUNT(*) FROM signoff s WHERE s.object_type = 'deployment' AND s.object_id = dr.id) AS total_gates,
    (SELECT COUNT(*) FROM signoff s WHERE s.object_type = 'deployment' AND s.object_id = dr.id AND s.decision = 'approved') AS approved_gates,
    (SELECT gate FROM v_gate_status gs
      WHERE gs.object_type = 'deployment' AND gs.object_id = dr.id AND gs.decision = 'pending'
      ORDER BY gs.sequence LIMIT 1) AS next_gate
FROM deployment_request dr
JOIN template t ON t.id = dr.template_id
JOIN chain ch ON ch.id = dr.chain_id
JOIN person req ON req.id = dr.requested_by
JOIN person owner ON owner.id = dr.business_owner_id
JOIN org_unit ou ON ou.id = dr.org_unit_id
JOIN v_deployment_readiness r ON r.id = dr.id;

CREATE VIEW v_attestation_alerts AS
SELECT
    a.id,
    a.attestation_type,
    a.provider,
    a.result,
    a.status,
    a.issued_at,
    a.expires_at,
    a.report_uri,
    a.instance_id,
    a.template_id,
    COALESCE(ci.product_name, t.name, a.attestation_type) AS subject,
    CAST(julianday(a.expires_at) - julianday('now') AS INTEGER) AS days_left,
    CASE
        WHEN a.status = 'expired' OR date(a.expires_at) < date('now') THEN 'expired'
        WHEN date(a.expires_at) <= date('now', '+30 days') THEN 'critical'
        WHEN date(a.expires_at) <= date('now', '+60 days') THEN 'warning'
        ELSE 'ok'
    END AS alert_level
FROM attestation a
LEFT JOIN contract_instance ci ON ci.id = a.instance_id
LEFT JOIN template t ON t.id = a.template_id
WHERE a.expires_at IS NOT NULL
  AND (a.status IN ('expired', 'revoked') OR date(a.expires_at) <= date('now', '+60 days'))
ORDER BY a.expires_at;

CREATE VIEW v_unlinked_discoveries AS
SELECT
    d.*,
    ch.name AS chain_name,
    ch.environment,
    t.name AS suspected_template_name,
    t.version AS suspected_template_version
FROM discovery_queue d
JOIN chain ch ON ch.id = d.chain_id
LEFT JOIN template t ON t.id = d.suspected_template_id
WHERE d.status IN ('new', 'triage', 'quarantined');

CREATE VIEW v_contract_links AS
SELECT
    l.id,
    l.from_instance_id,
    f.product_name AS from_name,
    f.address AS from_address,
    l.to_instance_id,
    t.product_name AS to_name,
    t.address AS to_address,
    l.relation,
    l.confidence,
    l.valid_from,
    l.valid_to,
    l.evidence_tx,
    l.notes
FROM contract_link l
JOIN contract_instance f ON f.id = l.from_instance_id
JOIN contract_instance t ON t.id = l.to_instance_id;

CREATE VIEW v_token_reserve AS
SELECT
    tm.instance_id,
    ci.product_name,
    ci.legal_entity,
    tm.symbol,
    tm.decimals,
    tm.total_supply,
    tm.asset_class,
    tm.underlying_asset,
    tm.custodian,
    tm.counts_toward_reserve,
    rp.pool_code,
    rp.description AS reserve_pool,
    rs.id AS snapshot_id,
    rs.as_of,
    rs.token_supply,
    rs.gold_grams,
    rs.coverage_ratio,
    rs.bars_count,
    rs.auditor,
    rs.verified,
    b.bar_grams,
    b.bar_rows,
    ROUND(COALESCE(b.bar_grams, 0) - rs.gold_grams, 4) AS bar_delta,
    CASE
        WHEN rs.id IS NOT NULL
         AND b.bar_rows = rs.bars_count
         AND abs(COALESCE(b.bar_grams, 0) - rs.gold_grams) < 0.001
        THEN 1 ELSE 0
    END AS bars_reconciled,
    ROUND(tm.total_supply - rs.token_supply, 4) AS supply_delta,
    CASE
        WHEN rs.as_of IS NULL THEN 'no reserve snapshot'
        WHEN rs.coverage_ratio < 1.0 THEN 'undercollateralised'
        WHEN date(rs.as_of) < date('now', '-45 days') THEN 'stale'
        ELSE 'current'
    END AS reserve_state
FROM token_metadata tm
JOIN contract_instance ci ON ci.id = tm.instance_id
LEFT JOIN reserve_pool rp ON rp.id = tm.reserve_pool_id
LEFT JOIN reserve_snapshot rs ON rs.pool_id = tm.reserve_pool_id AND rs.is_current = 1
LEFT JOIN (
    SELECT instance_id, COUNT(*) AS bar_rows, SUM(weight_grams) AS bar_grams
    FROM gold_bar GROUP BY instance_id
) b ON b.instance_id = tm.instance_id
WHERE tm.underlying_asset = 'XAU';

CREATE VIEW v_control_coverage AS
SELECT
    c.id,
    c.code,
    c.name,
    c.framework,
    c.control_type,
    c.frequency,
    COUNT(ic.id) AS instances_tested,
    SUM(CASE WHEN ic.status = 'pass' THEN 1 ELSE 0 END) AS passing,
    SUM(CASE WHEN ic.status IN ('fail', 'exception') THEN 1 ELSE 0 END) AS exceptions,
    SUM(CASE WHEN ic.status = 'not_tested' THEN 1 ELSE 0 END) AS not_tested
FROM control c
LEFT JOIN instance_control ic ON ic.control_id = c.id
GROUP BY c.id;

CREATE VIEW v_control_exceptions AS
SELECT
    ic.id,
    ic.instance_id,
    ci.product_name,
    ci.risk_tier,
    c.code AS control_code,
    c.name AS control_name,
    c.framework,
    ic.status,
    ic.notes,
    ic.last_tested_at,
    ic.next_test_due,
    ic.exception_approved_by,
    p.display_name AS exception_approver
FROM instance_control ic
JOIN control c ON c.id = ic.control_id
JOIN contract_instance ci ON ci.id = ic.instance_id
LEFT JOIN person p ON p.id = ic.exception_approved_by
WHERE ic.status IN ('fail', 'exception');

CREATE VIEW v_chain_health AS
SELECT
    ch.id AS chain_id,
    ch.name,
    ch.environment,
    ch.network_type,
    ch.status,
    ch.finality_blocks,
    COUNT(DISTINCT ci.id) AS registered_instances,
    COUNT(DISTINCT d.id) AS open_discoveries,
    (SELECT sr.status FROM sync_run sr WHERE sr.chain_id = ch.id ORDER BY sr.started_at DESC LIMIT 1) AS last_sync_status,
    (SELECT sr.finished_at FROM sync_run sr WHERE sr.chain_id = ch.id ORDER BY sr.started_at DESC LIMIT 1) AS last_sync_at,
    (SELECT sr.checkpoint_block FROM sync_run sr WHERE sr.chain_id = ch.id ORDER BY sr.started_at DESC LIMIT 1) AS checkpoint_block
FROM chain ch
LEFT JOIN contract_instance ci ON ci.chain_id = ch.id AND ci.instance_kind = 'logical'
LEFT JOIN discovery_queue d ON d.chain_id = ch.id AND d.status IN ('new', 'triage', 'quarantined')
GROUP BY ch.id;

CREATE VIEW v_role_holders AS
SELECT
    ra.id,
    ra.role_code,
    p.id AS person_id,
    p.display_name,
    p.email,
    ra.scope_org_unit_id,
    ou.name AS scope_org_unit,
    ra.active,
    ra.valid_from,
    ra.valid_to,
    ra.delegated_from_person_id
FROM role_assignment ra
JOIN person p ON p.id = ra.person_id
LEFT JOIN org_unit ou ON ou.id = ra.scope_org_unit_id;

CREATE VIEW v_request_bundle AS
SELECT
    dri.id,
    dri.request_id,
    dr.product_name,
    dri.item_role,
    dri.template_id,
    t.name AS template_name,
    t.version AS template_version,
    t.category,
    dri.instance_id,
    ci.address,
    ci.status AS instance_status,
    dri.config_hash
FROM deployment_request_item dri
JOIN deployment_request dr ON dr.id = dri.request_id
JOIN template t ON t.id = dri.template_id
LEFT JOIN contract_instance ci ON ci.id = dri.instance_id;

CREATE VIEW v_persona_summary AS
SELECT
    p.id,
    p.role_code,
    p.name,
    p.mandate,
    p.decision_rights,
    p.review_cadence,
    p.sort_order,
    COUNT(f.id) AS findings_total,
    SUM(CASE WHEN f.status = 'open' THEN 1 ELSE 0 END) AS findings_open,
    SUM(CASE WHEN f.status = 'open' AND f.severity IN ('critical', 'high') THEN 1 ELSE 0 END) AS findings_high_open,
    SUM(CASE WHEN f.status = 'risk_accepted' THEN 1 ELSE 0 END) AS findings_accepted,
    SUM(CASE WHEN f.status IN ('remediated', 'closed') THEN 1 ELSE 0 END) AS findings_closed
FROM persona p
LEFT JOIN persona_finding f ON f.persona_id = p.id
GROUP BY p.id;

CREATE VIEW v_persona_findings AS
SELECT
    f.id,
    f.persona_id,
    p.role_code,
    p.name AS persona_name,
    f.object_type,
    f.object_id,
    f.severity,
    f.title,
    f.issue,
    f.recommendation,
    f.status,
    f.owner_person_id,
    owner.display_name AS owner_name,
    f.accepted_by,
    accepted.display_name AS accepted_by_name,
    f.due_date,
    f.expires_at,
    f.evidence_uri,
    f.created_at,
    f.updated_at
FROM persona_finding f
JOIN persona p ON p.id = f.persona_id
LEFT JOIN person owner ON owner.id = f.owner_person_id
LEFT JOIN person accepted ON accepted.id = f.accepted_by;

CREATE VIEW v_compliance_coverage AS
SELECT
    cp.instance_id,
    ci.product_name,
    ci.legal_entity,
    ci.jurisdiction,
    ci.risk_tier,
    cp.regulatory_classification,
    cp.mica_type,
    cp.instrument_id,
    cp.aml_risk_rating,
    cp.sanctions_screening,
    cp.travel_rule,
    cp.dpia_ref,
    cp.dora_register_ref,
    cp.redemption_sla,
    cp.status,
    cp.last_reviewed_at,
    reviewer.display_name AS reviewed_by_name,
    (SELECT COUNT(*) FROM persona_finding f
      WHERE f.object_type = 'contract' AND f.object_id = ci.id AND f.status = 'open') AS open_findings
FROM compliance_profile cp
JOIN contract_instance ci ON ci.id = cp.instance_id
LEFT JOIN person reviewer ON reviewer.id = cp.reviewed_by
WHERE ci.instance_kind = 'logical';

CREATE VIEW v_ict_coverage AS
SELECT
    tp.id AS provider_id,
    tp.name AS provider,
    tp.lei,
    tp.service,
    tp.criticality,
    tp.data_location,
    tp.contract_ref,
    tp.dora_register_ref,
    tp.exit_plan,
    tp.last_reviewed_at,
    COUNT(DISTINCT ii.instance_id) AS linked_instances,
    GROUP_CONCAT(DISTINCT ci.product_name) AS products
FROM ict_third_party tp
LEFT JOIN instance_ict ii ON ii.provider_id = tp.id
LEFT JOIN contract_instance ci ON ci.id = ii.instance_id
GROUP BY tp.id;

CREATE VIEW v_signoff_evidence_gaps AS
SELECT
    s.id AS signoff_id,
    s.object_type,
    s.object_id,
    s.gate,
    s.required_role,
    s.decision,
    s.decided_by,
    p.display_name AS decided_by_name,
    s.decided_at,
    s.evidence_uri,
    s.evidence_hash,
    s.document_id,
    CASE
        WHEN s.evidence_hash IS NULL THEN 'missing hash'
        WHEN s.document_id IS NULL THEN 'missing document link'
        WHEN s.evidence_uri LIKE 'evidence://%' THEN 'placeholder evidence URI'
        ELSE 'evidence present'
    END AS gap
FROM signoff s
LEFT JOIN person p ON p.id = s.decided_by
WHERE s.decision = 'approved'
  AND (s.evidence_hash IS NULL OR s.document_id IS NULL OR s.evidence_uri LIKE 'evidence://%');

CREATE VIEW v_template_gate_gaps AS
SELECT
    t.id,
    t.name,
    t.version,
    t.status,
    t.default_risk_tier,
    (SELECT COUNT(*) FROM signoff s WHERE s.object_type = 'template' AND s.object_id = t.id) AS gates,
    (SELECT COUNT(*) FROM signoff s WHERE s.object_type = 'template' AND s.object_id = t.id AND s.decision = 'approved') AS approved_gates,
    (SELECT COUNT(*) FROM signoff s WHERE s.object_type = 'template' AND s.object_id = t.id AND s.decision = 'pending') AS pending_gates
FROM template t
WHERE t.status = 'approved'
  AND t.default_risk_tier IN ('high', 'critical');

CREATE VIEW v_deployer_risk AS
SELECT
    ci.id,
    ci.product_name,
    ci.chain_id,
    ci.address,
    ci.risk_tier,
    ci.signing_identity_id,
    si.name AS signing_identity,
    si.key_type,
    si.allowlisted,
    ci.deployer_address,
    ci.deployer_type
FROM contract_instance ci
LEFT JOIN signing_identity si ON si.id = ci.signing_identity_id
WHERE ci.instance_kind = 'logical'
  AND (si.allowlisted = 0 OR si.id IS NULL);

CREATE VIEW v_reserve_reconciliation AS
SELECT
    instance_id,
    product_name,
    symbol,
    reserve_pool,
    counts_toward_reserve,
    total_supply,
    token_supply,
    supply_delta,
    gold_grams,
    bar_grams,
    bar_rows,
    bars_count,
    bar_delta,
    bars_reconciled,
    reserve_state
FROM v_token_reserve;
