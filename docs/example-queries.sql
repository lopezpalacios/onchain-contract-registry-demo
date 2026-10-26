-- Example registry queries for the SQLite demo.
-- Run with: sqlite3 -header -column data/registry.db < docs/example-queries.sql

-- 1. Inventory: one row per logical deployment
SELECT id, product_name, chain_name, template_name, template_version,
       risk_tier, status, template_audit_state
FROM v_inventory
ORDER BY risk_tier DESC, product_name;

-- 2. Template reuse: how many deployments from each template, and where?
SELECT name, version, status, deployments, chains_used, chain_names
FROM v_template_usage
WHERE deployments > 0
ORDER BY deployments DESC;

-- 3. Template → instance traceability for the gold token family
SELECT t.template_key, t.version, ci.product_name, ch.name AS chain,
       ci.address, ci.proxy_type, ci.implementation_address
FROM contract_instance ci
JOIN template t ON t.id = ci.template_id
JOIN chain ch ON ch.id = ci.chain_id
WHERE t.template_key IN ('CMTAT_STANDARD', 'CMTAT_UUPS')
ORDER BY t.version, ch.name, ci.product_name;

-- 4. Proxy bindings and their implementation records
SELECT f.product_name AS proxy_product, f.address AS proxy_address,
       t.product_name AS implementation_name, t.address AS implementation_address
FROM contract_link l
JOIN contract_instance f ON f.id = l.from_instance_id
JOIN contract_instance t ON t.id = l.to_instance_id
WHERE l.relation = 'delegates_to';

-- 5. Pending gates by request and required role
SELECT object_id, gate, required_role, sequence,
       decided_by_name, decision
FROM v_gate_status
WHERE object_type = 'deployment' AND decision = 'pending'
ORDER BY object_id, sequence;

-- 6. Requests that are blocked or in review
SELECT id, product_name, chain_name, risk_tier, status, readiness,
       pending_blocking_gates, next_gate
FROM v_pending_approvals
WHERE status = 'in_review'
ORDER BY created_at;

-- 7. Reserve coverage by pool (exclude test / retired supply)
SELECT instance_id, product_name, symbol, reserve_pool,
       total_supply, gold_grams, coverage_ratio, reserve_state,
       counts_toward_reserve
FROM v_token_reserve
ORDER BY counts_toward_reserve DESC, instance_id;

-- 8. Expiring or expired evidence
SELECT subject, attestation_type, provider, expires_at, days_left, alert_level
FROM v_attestation_alerts
ORDER BY expires_at;

-- 9. Unknown / unlinked on-chain contracts
SELECT id, chain_name, address, status, risk_hint, classification, notes
FROM v_unlinked_discoveries
ORDER BY risk_hint DESC, first_seen_at;

-- 10. Control exceptions and the accepting owner
SELECT instance_id, product_name, control_code, control_name,
       status, exception_approver, notes
FROM v_control_exceptions
ORDER BY control_code, product_name;

-- 11. Admin roles that are not held by a Safe or Timelock
SELECT ci.product_name, ci.admin_address, ci.risk_tier
FROM contract_instance ci
WHERE ci.admin_address IS NOT NULL
  AND ci.admin_address NOT IN (
      SELECT address FROM contract_instance
      WHERE template_id IN ('tpl-safe-140', 'tpl-timelock-100')
  );

-- 12. Segregation-of-duties sanity check: requester named as an approver
SELECT dr.id AS request_id, dr.requested_by, s.gate, s.decided_by, s.decision
FROM deployment_request dr
JOIN signoff s ON s.object_type = 'deployment' AND s.object_id = dr.id
WHERE s.decided_by = dr.requested_by
ORDER BY dr.id, s.gate;

-- 13. DORA-style export stub: product, legal entity, chain, owner, criticality, evidence
SELECT ci.product_name, ci.legal_entity, ci.jurisdiction, ch.name AS chain,
       p.display_name AS business_owner, ou.division, ci.criticality,
       ci.risk_tier, ci.status,
       (SELECT COUNT(*) FROM attestation a
         WHERE (a.instance_id = ci.id OR a.template_id = ci.template_id)
           AND a.status = 'valid') AS valid_evidence
FROM contract_instance ci
JOIN chain ch ON ch.id = ci.chain_id
LEFT JOIN person p ON p.id = ci.business_owner_id
LEFT JOIN org_unit ou ON ou.id = ci.org_unit_id
WHERE ci.instance_kind = 'logical'
ORDER BY ci.risk_tier DESC, ci.product_name;

-- 14. Recent on-chain events linked to known contracts
SELECT ch.name AS chain, ci.product_name, e.block_number, e.event_name,
       e.tx_hash, e.observed_at
FROM onchain_event e
JOIN chain ch ON ch.id = e.chain_id
LEFT JOIN contract_instance ci ON ci.id = e.instance_id
ORDER BY e.block_number DESC
LIMIT 20;

-- 15. Council: open findings by role and severity
SELECT p.name AS role, p.mandate, p.findings_open, p.findings_high_open
FROM v_persona_summary p
ORDER BY p.sort_order;

-- 16. Council: open findings with owner and due date
SELECT f.severity, f.persona_name, f.title, f.owner_name, f.due_date, f.status
FROM v_persona_findings f
WHERE f.status = 'open'
ORDER BY CASE f.severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END;

-- 17. Compliance coverage by product
SELECT product_name, regulatory_classification, aml_risk_rating,
       sanctions_screening, dora_register_ref, status, open_findings
FROM v_compliance_coverage
ORDER BY risk_tier DESC, product_name;

-- 18. Evidence gaps, ICT dependencies and reserve reconciliation
SELECT object_id, gate, decided_by_name, gap
FROM v_signoff_evidence_gaps
ORDER BY object_id, gate;

SELECT provider, service, criticality, data_location, dora_register_ref
FROM v_ict_coverage
ORDER BY provider;

SELECT instance_id, product_name, total_supply, token_supply, supply_delta,
       gold_grams, bar_grams, bars_reconciled
FROM v_reserve_reconciliation
ORDER BY instance_id;
