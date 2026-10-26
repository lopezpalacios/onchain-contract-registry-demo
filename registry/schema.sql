-- Smart Contract Inventory & Control Registry
-- SQLite 3.35+ / STRICT tables
-- Design note: use integer base units or DECIMAL in production for money.
-- This demo stores display amounts as REAL to keep queries readable.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ---------------------------------------------------------------------------
-- 1. Reference data
-- ---------------------------------------------------------------------------

CREATE TABLE chain (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    caip2             TEXT NOT NULL UNIQUE,
    chain_id          INTEGER NOT NULL UNIQUE,
    network_type      TEXT NOT NULL CHECK (network_type IN ('public', 'private', 'consortium')),
    environment       TEXT NOT NULL CHECK (environment IN ('DEV', 'UAT', 'PROD')),
    consensus         TEXT,
    privacy_mode      TEXT,
    permissioning     TEXT,
    rpc_endpoint      TEXT,
    rpc_secret_ref    TEXT,
    explorer_url      TEXT,
    genesis_hash      TEXT,
    finality_blocks   INTEGER NOT NULL DEFAULT 12,
    sync_enabled      INTEGER NOT NULL DEFAULT 1,
    status            TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'degraded', 'offline', 'retired')),
    created_at        TEXT NOT NULL DEFAULT (datetime('now'))
) STRICT;

CREATE TABLE org_unit (
    id              TEXT PRIMARY KEY,
    code            TEXT NOT NULL UNIQUE,
    name            TEXT NOT NULL,
    parent_id       TEXT REFERENCES org_unit(id),
    division        TEXT NOT NULL,
    cost_center     TEXT,
    legal_entity    TEXT
) STRICT;

CREATE TABLE person (
    id              TEXT PRIMARY KEY,
    upn             TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    email           TEXT NOT NULL,
    title           TEXT,
    org_unit_id     TEXT REFERENCES org_unit(id),
    active          INTEGER NOT NULL DEFAULT 1,
    leaver_date     TEXT
) STRICT;

CREATE TABLE role_assignment (
    id                      TEXT PRIMARY KEY,
    person_id               TEXT NOT NULL REFERENCES person(id),
    role_code               TEXT NOT NULL,
    scope_org_unit_id       TEXT REFERENCES org_unit(id),
    active                  INTEGER NOT NULL DEFAULT 1,
    valid_from              TEXT,
    valid_to                TEXT,
    delegated_from_person_id TEXT REFERENCES person(id),
    UNIQUE (person_id, role_code, scope_org_unit_id)
) STRICT;

CREATE TABLE signing_identity (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    key_type            TEXT NOT NULL CHECK (key_type IN ('hsm', 'kms', 'eoa', 'contract', 'ci-oidc', 'multisig', 'timelock')),
    provider            TEXT,
    owner_person_id     TEXT REFERENCES person(id),
    allowlisted         INTEGER NOT NULL DEFAULT 0,
    valid_from          TEXT,
    valid_to            TEXT,
    last_used_at        TEXT,
    evidence_uri        TEXT
) STRICT;

CREATE TABLE ict_third_party (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    lei                 TEXT,
    service             TEXT NOT NULL,
    criticality         TEXT NOT NULL CHECK (criticality IN ('low', 'medium', 'high', 'critical')),
    contract_ref        TEXT,
    data_location       TEXT,
    subcontractors      TEXT,
    exit_plan           TEXT,
    dora_register_ref   TEXT,
    last_reviewed_at    TEXT
) STRICT;

CREATE TABLE persona (
    id                  TEXT PRIMARY KEY,
    role_code           TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    mandate             TEXT NOT NULL,
    decision_rights     TEXT NOT NULL,
    review_cadence      TEXT NOT NULL,
    sort_order          INTEGER NOT NULL
) STRICT;

CREATE TABLE persona_finding (
    id                  TEXT PRIMARY KEY,
    persona_id          TEXT NOT NULL REFERENCES persona(id),
    object_type         TEXT NOT NULL CHECK (object_type IN ('contract', 'template', 'deployment_request', 'control', 'process', 'incident')),
    object_id           TEXT,
    severity            TEXT NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
    title               TEXT NOT NULL,
    issue               TEXT NOT NULL,
    recommendation      TEXT NOT NULL,
    status              TEXT NOT NULL CHECK (status IN ('open', 'accepted', 'remediated', 'closed', 'risk_accepted')),
    owner_person_id     TEXT REFERENCES person(id),
    accepted_by         TEXT REFERENCES person(id),
    due_date            TEXT,
    expires_at          TEXT,
    evidence_uri        TEXT,
    created_at          TEXT NOT NULL,
    updated_at          TEXT
) STRICT;

CREATE TABLE standard (
    code            TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    family          TEXT NOT NULL,
    url             TEXT,
    status          TEXT NOT NULL DEFAULT 'final' CHECK (status IN ('final', 'draft', 'internal', 'deprecated')),
    notes           TEXT
) STRICT;

-- ---------------------------------------------------------------------------
-- 2. Templates = the approved code artifact, not a deployment
-- ---------------------------------------------------------------------------

CREATE TABLE template (
    id                  TEXT PRIMARY KEY,
    template_key        TEXT NOT NULL,
    name                TEXT NOT NULL,
    version             TEXT NOT NULL,
    category            TEXT NOT NULL CHECK (category IN (
                            'token', 'compliance', 'settlement', 'value', 'utility',
                            'proxy', 'factory', 'identity', 'oracle', 'governance',
                            'account', 'interop', 'privacy', 'attestation')),
    contract_type       TEXT NOT NULL,
    description         TEXT,
    source_repo         TEXT,
    source_path         TEXT,
    git_commit          TEXT,
    compiler_version    TEXT,
    evm_version         TEXT,
    license             TEXT,
    initcode_hash       TEXT NOT NULL,
    runtime_code_hash   TEXT NOT NULL,
    abi_hash            TEXT,
    audit_status        TEXT NOT NULL CHECK (audit_status IN ('none', 'self', 'internal', 'external')),
    audit_provider      TEXT,
    audit_valid_until   TEXT,
    ethtrust_level      TEXT CHECK (ethtrust_level IN ('S', 'M', 'Q') OR ethtrust_level IS NULL),
    default_risk_tier   TEXT NOT NULL CHECK (default_risk_tier IN ('low', 'medium', 'high', 'critical')),
    owner_org_unit_id   TEXT NOT NULL REFERENCES org_unit(id),
    status              TEXT NOT NULL CHECK (status IN ('draft', 'approved', 'deprecated', 'blocked')),
    approved_at         TEXT,
    retired_at          TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    notes               TEXT,
    UNIQUE (template_key, version)
) STRICT;

CREATE TABLE template_standard (
    template_id     TEXT NOT NULL REFERENCES template(id),
    standard_code   TEXT NOT NULL REFERENCES standard(code),
    conformance     TEXT NOT NULL CHECK (conformance IN ('full', 'partial', 'reference')),
    notes           TEXT,
    PRIMARY KEY (template_id, standard_code)
) STRICT;

CREATE TABLE template_dependency (
    id                      TEXT PRIMARY KEY,
    template_id             TEXT NOT NULL REFERENCES template(id),
    depends_on_template_id  TEXT NOT NULL REFERENCES template(id),
    relation                TEXT NOT NULL CHECK (relation IN ('inherits', 'uses', 'requires', 'compatible_with')),
    version_constraint      TEXT,
    UNIQUE (template_id, depends_on_template_id, relation)
) STRICT;

CREATE TABLE template_parameter (
    id              TEXT PRIMARY KEY,
    template_id     TEXT NOT NULL REFERENCES template(id),
    name            TEXT NOT NULL,
    data_type       TEXT NOT NULL,
    required        INTEGER NOT NULL DEFAULT 1,
    default_value   TEXT,
    description     TEXT,
    sensitive       INTEGER NOT NULL DEFAULT 0,
    UNIQUE (template_id, name)
) STRICT;

CREATE TABLE software_ci (
    id                  TEXT PRIMARY KEY,
    ci_name             TEXT NOT NULL,
    ci_type             TEXT NOT NULL,
    owner_org_unit_id   TEXT REFERENCES org_unit(id),
    support_group       TEXT,
    lifecycle_status    TEXT NOT NULL CHECK (lifecycle_status IN ('planned', 'active', 'maintenance', 'retired')),
    criticality         TEXT NOT NULL CHECK (criticality IN ('low', 'medium', 'high', 'critical')),
    cmdb_url            TEXT
) STRICT;

CREATE TABLE template_ci (
    template_id     TEXT NOT NULL REFERENCES template(id),
    ci_id           TEXT NOT NULL REFERENCES software_ci(id),
    relation        TEXT NOT NULL CHECK (relation IN ('runs_on', 'owned_by', 'part_of')),
    PRIMARY KEY (template_id, ci_id, relation)
) STRICT;

-- ---------------------------------------------------------------------------
-- 3. Deployment requests, policies, and evidence-based sign-offs
-- ---------------------------------------------------------------------------

CREATE TABLE deployment_request (
    id                      TEXT PRIMARY KEY,
    template_id             TEXT NOT NULL REFERENCES template(id),
    chain_id                TEXT NOT NULL REFERENCES chain(id),
    environment             TEXT NOT NULL CHECK (environment IN ('DEV', 'UAT', 'PROD')),
    requested_by            TEXT NOT NULL REFERENCES person(id),
    business_owner_id       TEXT NOT NULL REFERENCES person(id),
    org_unit_id             TEXT NOT NULL REFERENCES org_unit(id),
    product_name            TEXT NOT NULL,
    legal_entity            TEXT NOT NULL,
    jurisdiction            TEXT NOT NULL,
    risk_tier               TEXT NOT NULL CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),
    config_hash             TEXT NOT NULL,
    init_params_json        TEXT,
    salt                    TEXT,
    manifest_hash           TEXT,
    status                  TEXT NOT NULL CHECK (status IN ('draft', 'in_review', 'approved', 'rejected', 'deployed', 'cancelled')),
    change_ticket           TEXT,
    target_window           TEXT,
    created_at              TEXT NOT NULL,
    approved_at             TEXT,
    notes                   TEXT
) STRICT;

CREATE TABLE deployment_request_item (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id      TEXT NOT NULL REFERENCES deployment_request(id),
    template_id     TEXT NOT NULL REFERENCES template(id),
    item_role       TEXT NOT NULL CHECK (item_role IN ('primary', 'compliance', 'identity', 'proxy', 'oracle', 'settlement', 'governance', 'utility', 'reserve')),
    instance_id     TEXT REFERENCES contract_instance(id),
    config_hash     TEXT,
    notes           TEXT,
    UNIQUE (request_id, template_id, item_role)
) STRICT;

CREATE TABLE approval_policy (
    id              TEXT PRIMARY KEY,
    object_type     TEXT NOT NULL CHECK (object_type IN ('template', 'deployment', 'change', 'instance')),
    risk_tier       TEXT NOT NULL CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),
    gate            TEXT NOT NULL,
    required_role   TEXT NOT NULL,
    min_approvals   INTEGER NOT NULL DEFAULT 1 CHECK (min_approvals >= 1),
    blocking        INTEGER NOT NULL DEFAULT 1,
    sequence        INTEGER NOT NULL,
    description     TEXT,
    UNIQUE (object_type, risk_tier, gate, required_role)
) STRICT;

CREATE TABLE signoff (
    id              TEXT PRIMARY KEY,
    object_type     TEXT NOT NULL CHECK (object_type IN ('template', 'deployment', 'change', 'instance')),
    object_id       TEXT NOT NULL,
    gate            TEXT NOT NULL,
    required_role   TEXT NOT NULL,
    decision        TEXT NOT NULL DEFAULT 'pending'
                    CHECK (decision IN ('pending', 'approved', 'rejected', 'abstained', 'expired')),
    decided_by      TEXT REFERENCES person(id),
    decided_at      TEXT,
    comments        TEXT,
    evidence_uri    TEXT,
    evidence_hash   TEXT,
    document_id     TEXT,
    auth_method     TEXT NOT NULL DEFAULT 'seed',
    expires_at      TEXT,
    delegated_from  TEXT REFERENCES person(id),
    created_at      TEXT NOT NULL
) STRICT;

CREATE INDEX ix_signoff_object ON signoff(object_type, object_id, decision);
CREATE INDEX ix_signoff_next ON signoff(object_id, gate, required_role, decision);

-- ---------------------------------------------------------------------------
-- 4. On-chain instances and their relationships
-- ---------------------------------------------------------------------------

CREATE TABLE contract_instance (
    id                      TEXT PRIMARY KEY,
    chain_id                TEXT NOT NULL REFERENCES chain(id),
    address                 TEXT NOT NULL,
    template_id             TEXT NOT NULL REFERENCES template(id),
    instance_kind           TEXT NOT NULL DEFAULT 'logical'
                            CHECK (instance_kind IN ('logical', 'implementation', 'supporting')),
    representation          TEXT NOT NULL DEFAULT 'native'
                            CHECK (representation IN ('native', 'mirror', 'wrapped', 'receipt', 'not_applicable')),
    deployment_request_id   TEXT REFERENCES deployment_request(id),
    deployment_tx           TEXT,
    deployer_address        TEXT,
    deployer_type           TEXT CHECK (deployer_type IN ('eoa', 'hsm', 'contract', 'multisig', 'service')),
    signing_identity_id     TEXT REFERENCES signing_identity(id),
    block_number            INTEGER,
    deployed_at             TEXT,
    salt                    TEXT,
    init_code_hash          TEXT,
    runtime_code_hash       TEXT NOT NULL,
    proxy_type              TEXT CHECK (proxy_type IN ('none', 'eip1967-transparent', 'eip1967-uups', 'beacon', 'eip1167-clone', 'diamond', 'custom')),
    implementation_address  TEXT,
    admin_address           TEXT,
    beacon_address          TEXT,
    status                  TEXT NOT NULL CHECK (status IN ('proposed', 'deployed', 'active', 'paused', 'deprecated', 'retired', 'quarantined')),
    business_owner_id       TEXT REFERENCES person(id),
    org_unit_id             TEXT REFERENCES org_unit(id),
    legal_entity            TEXT,
    jurisdiction            TEXT,
    product_name            TEXT,
    classification          TEXT,
    risk_tier               TEXT NOT NULL CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),
    criticality             TEXT,
    privacy_group           TEXT,
    is_canonical            INTEGER NOT NULL DEFAULT 0,
    supersedes_id           TEXT REFERENCES contract_instance(id),
    verification_status     TEXT NOT NULL CHECK (verification_status IN ('unverified', 'partial', 'exact', 'match', 'failed')),
    verification_provider   TEXT,
    verification_url        TEXT,
    verified_at             TEXT,
    last_synced_at          TEXT,
    notes                   TEXT,
    UNIQUE (chain_id, address)
) STRICT;

CREATE INDEX ix_instance_template ON contract_instance(template_id);
CREATE INDEX ix_instance_chain ON contract_instance(chain_id);
CREATE INDEX ix_instance_kind ON contract_instance(instance_kind);

CREATE TABLE instance_parameter (
    id              TEXT PRIMARY KEY,
    instance_id     TEXT NOT NULL REFERENCES contract_instance(id),
    name            TEXT NOT NULL,
    value           TEXT,
    value_hash      TEXT,
    source          TEXT NOT NULL CHECK (source IN ('constructor', 'initializer', 'admin_call', 'immutable')),
    is_sensitive    INTEGER NOT NULL DEFAULT 0,
    UNIQUE (instance_id, name)
) STRICT;

CREATE TABLE reserve_pool (
    id                  TEXT PRIMARY KEY,
    pool_code           TEXT NOT NULL UNIQUE,
    description         TEXT NOT NULL,
    asset               TEXT NOT NULL,
    custodian           TEXT NOT NULL,
    legal_entity        TEXT NOT NULL,
    vault_location      TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
) STRICT;

CREATE TABLE token_metadata (
    instance_id             TEXT PRIMARY KEY REFERENCES contract_instance(id),
    token_name              TEXT NOT NULL,
    symbol                  TEXT NOT NULL,
    decimals                INTEGER NOT NULL,
    total_supply            REAL NOT NULL,
    asset_class             TEXT NOT NULL,
    underlying_asset        TEXT,
    custodian               TEXT,
    isin                    TEXT,
    currency                TEXT,
    supply_scope            TEXT,
    reserve_pool_id         TEXT REFERENCES reserve_pool(id),
    counts_toward_reserve   INTEGER NOT NULL DEFAULT 1,
    kyc_required            INTEGER NOT NULL DEFAULT 1,
    transfer_restrictions   TEXT,
    proof_of_reserve_uri    TEXT,
    redemption_terms_uri    TEXT,
    valuation_source        TEXT
) STRICT;

CREATE TABLE reserve_snapshot (
    id                  TEXT PRIMARY KEY,
    instance_id         TEXT REFERENCES contract_instance(id),
    pool_id             TEXT REFERENCES reserve_pool(id),
    as_of               TEXT NOT NULL,
    token_supply        REAL NOT NULL,
    gold_grams          REAL NOT NULL,
    coverage_ratio      REAL NOT NULL,
    bars_count          INTEGER NOT NULL,
    auditor             TEXT NOT NULL,
    report_document_id  TEXT,
    is_current          INTEGER NOT NULL DEFAULT 0,
    verified            INTEGER NOT NULL DEFAULT 1,
    notes               TEXT
) STRICT;

CREATE TABLE compliance_profile (
    instance_id             TEXT PRIMARY KEY REFERENCES contract_instance(id),
    regulatory_classification TEXT NOT NULL,
    mica_type               TEXT,
    instrument_id           TEXT,
    fungibility_group       TEXT,
    prospectus_ref          TEXT,
    legal_structure         TEXT,
    holder_claim_type       TEXT,
    segregation_basis       TEXT,
    insolvency_remoteness   TEXT,
    custody_agreement_ref   TEXT,
    legal_title_ref         TEXT,
    aml_risk_rating         TEXT NOT NULL CHECK (aml_risk_rating IN ('low', 'medium', 'high', 'critical')),
    client_eligibility      TEXT,
    sanctions_screening     TEXT,
    travel_rule             TEXT,
    distribution_countries  TEXT,
    investor_type           TEXT,
    target_market           TEXT,
    dpia_ref                TEXT,
    dpo_assessment          TEXT,
    onchain_pii_risk        TEXT,
    privacy_group_members   TEXT,
    dora_register_ref       TEXT,
    ict_third_party_ref     TEXT,
    exit_plan               TEXT,
    concentration_risk      TEXT,
    redemption_rights       TEXT,
    redemption_sla          TEXT,
    complaint_handling      TEXT,
    records_retention       TEXT,
    tax_treatment           TEXT,
    status                  TEXT NOT NULL CHECK (status IN ('complete', 'partial', 'gap')),
    last_reviewed_at        TEXT,
    reviewed_by             TEXT REFERENCES person(id)
) STRICT;

CREATE TABLE instance_ict (
    instance_id         TEXT NOT NULL REFERENCES contract_instance(id),
    provider_id         TEXT NOT NULL REFERENCES ict_third_party(id),
    dependency_type     TEXT NOT NULL,
    critical            INTEGER NOT NULL DEFAULT 1,
    evidence_uri        TEXT,
    PRIMARY KEY (instance_id, provider_id, dependency_type)
) STRICT;

CREATE UNIQUE INDEX ux_reserve_snapshot_current
    ON reserve_snapshot(pool_id) WHERE is_current = 1;

CREATE TABLE gold_bar (
    id              TEXT PRIMARY KEY,
    instance_id     TEXT NOT NULL REFERENCES contract_instance(id),
    serial_number   TEXT NOT NULL UNIQUE,
    refinery        TEXT NOT NULL,
    purity          TEXT NOT NULL,
    weight_grams    REAL NOT NULL,
    vault           TEXT NOT NULL,
    vault_location  TEXT NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('allocated', 'in_transit', 'pledged', 'released')),
    last_audit_at   TEXT
) STRICT;

CREATE TABLE contract_link (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    from_instance_id    TEXT NOT NULL REFERENCES contract_instance(id),
    to_instance_id      TEXT NOT NULL REFERENCES contract_instance(id),
    relation            TEXT NOT NULL CHECK (relation IN (
                            'delegates_to', 'admin_controlled_by', 'uses_rule_engine',
                            'uses_identity_registry', 'reads_trusted_issuers', 'reads_claim_topics',
                            'contains_rule', 'prices_from', 'reads_price_feed', 'settles_with',
                            'collateralised_by', 'attested_by', 'deployed_by_factory',
                            'mirrors', 'guards', 'supersedes')),
    confidence          TEXT NOT NULL DEFAULT 'confirmed' CHECK (confidence IN ('confirmed', 'inferred', 'declared')),
    valid_from          TEXT,
    valid_to            TEXT,
    evidence_tx         TEXT,
    notes               TEXT,
    UNIQUE (from_instance_id, to_instance_id, relation)
) STRICT;

CREATE TABLE instance_role (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    instance_id         TEXT NOT NULL REFERENCES contract_instance(id),
    role_name           TEXT NOT NULL,
    holder_address      TEXT NOT NULL,
    holder_type         TEXT NOT NULL CHECK (holder_type IN ('eoa', 'contract', 'multisig', 'timelock', 'hsm')),
    holder_instance_id  TEXT REFERENCES contract_instance(id),
    person_id           TEXT REFERENCES person(id),
    status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
    assigned_at         TEXT,
    revoked_at          TEXT,
    source_event_id     INTEGER,
    UNIQUE (instance_id, role_name, holder_address)
) STRICT;

-- ---------------------------------------------------------------------------
-- 5. Documents, attestations, events, changes, incidents, controls
-- ---------------------------------------------------------------------------

CREATE TABLE document (
    id                  TEXT PRIMARY KEY,
    object_type         TEXT NOT NULL CHECK (object_type IN ('template', 'instance', 'deployment_request', 'change_request')),
    object_id           TEXT NOT NULL,
    doc_type            TEXT NOT NULL,
    title               TEXT NOT NULL,
    uri                 TEXT NOT NULL,
    sha256              TEXT NOT NULL,
    version             TEXT,
    valid_from          TEXT,
    valid_to            TEXT,
    onchain_anchor_tx   TEXT,
    confidentiality     TEXT NOT NULL DEFAULT 'internal' CHECK (confidentiality IN ('public', 'internal', 'confidential', 'restricted')),
    uploaded_by         TEXT REFERENCES person(id),
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    retention_until     TEXT
) STRICT;

CREATE INDEX ix_document_object ON document(object_type, object_id);

CREATE TABLE attestation (
    id                  TEXT PRIMARY KEY,
    instance_id         TEXT REFERENCES contract_instance(id),
    template_id         TEXT REFERENCES template(id),
    attestation_type    TEXT NOT NULL,
    provider            TEXT NOT NULL,
    result              TEXT NOT NULL,
    score               TEXT,
    report_uri          TEXT,
    report_hash         TEXT,
    issued_at           TEXT,
    expires_at          TEXT,
    status              TEXT NOT NULL CHECK (status IN ('valid', 'expired', 'revoked', 'pending')),
    onchain_attestation_uid TEXT,
    notes               TEXT
) STRICT;

CREATE INDEX ix_attestation_expiry ON attestation(status, expires_at);

CREATE TABLE onchain_event (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chain_id        TEXT NOT NULL REFERENCES chain(id),
    instance_id     TEXT REFERENCES contract_instance(id),
    block_number    INTEGER NOT NULL,
    block_hash      TEXT,
    tx_hash         TEXT NOT NULL,
    log_index       INTEGER NOT NULL DEFAULT 0,
    event_name      TEXT NOT NULL,
    signature       TEXT,
    payload_json    TEXT,
    removed         INTEGER NOT NULL DEFAULT 0,
    observed_at     TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (chain_id, tx_hash, log_index)
) STRICT;

CREATE TABLE change_request (
    id              TEXT PRIMARY KEY,
    instance_id     TEXT NOT NULL REFERENCES contract_instance(id),
    change_type     TEXT NOT NULL CHECK (change_type IN ('upgrade', 'parameter', 'role', 'pause', 'unpause', 'migration', 'decommission')),
    description     TEXT NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('draft', 'in_review', 'approved', 'rejected', 'implemented', 'cancelled')),
    risk_tier       TEXT NOT NULL CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),
    requested_by    TEXT NOT NULL REFERENCES person(id),
    change_ticket   TEXT,
    created_at      TEXT NOT NULL,
    approved_at     TEXT,
    implemented_at  TEXT,
    implementation_tx TEXT,
    notes           TEXT
) STRICT;

CREATE TABLE incident (
    id                      TEXT PRIMARY KEY,
    instance_id             TEXT REFERENCES contract_instance(id),
    discovery_id            TEXT,
    change_request_id       TEXT REFERENCES change_request(id),
    severity                TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status                  TEXT NOT NULL CHECK (status IN ('open', 'investigating', 'contained', 'closed')),
    title                   TEXT NOT NULL,
    summary                 TEXT,
    opened_at               TEXT NOT NULL,
    contained_at            TEXT,
    closed_at               TEXT,
    playbook                TEXT,
    postmortem_uri          TEXT,
    regulatory_reportable   INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE TABLE control (
    id                  TEXT PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    framework           TEXT NOT NULL,
    description         TEXT,
    control_type        TEXT NOT NULL CHECK (control_type IN ('preventive', 'detective', 'corrective')),
    frequency           TEXT NOT NULL,
    owner_org_unit_id   TEXT REFERENCES org_unit(id)
) STRICT;

CREATE TABLE instance_control (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    instance_id         TEXT NOT NULL REFERENCES contract_instance(id),
    control_id          TEXT NOT NULL REFERENCES control(id),
    status              TEXT NOT NULL CHECK (status IN ('pass', 'fail', 'exception', 'not_tested', 'not_applicable')),
    evidence_uri        TEXT,
    last_tested_at      TEXT,
    tested_by           TEXT,
    next_test_due       TEXT,
    exception_approved_by TEXT REFERENCES person(id),
    notes               TEXT,
    UNIQUE (instance_id, control_id)
) STRICT;

-- ---------------------------------------------------------------------------
-- 6. Discovery / reconciliation with Besu (or any EVM RPC)
-- ---------------------------------------------------------------------------

CREATE TABLE sync_run (
    id                  TEXT PRIMARY KEY,
    chain_id            TEXT NOT NULL REFERENCES chain(id),
    mode                TEXT NOT NULL CHECK (mode IN ('backfill', 'incremental', 'manual', 'mock')),
    from_block          INTEGER NOT NULL,
    to_block            INTEGER NOT NULL,
    blocks_scanned      INTEGER NOT NULL DEFAULT 0,
    txs_scanned         INTEGER NOT NULL DEFAULT 0,
    contracts_found     INTEGER NOT NULL DEFAULT 0,
    contracts_matched   INTEGER NOT NULL DEFAULT 0,
    unknown             INTEGER NOT NULL DEFAULT 0,
    errors              INTEGER NOT NULL DEFAULT 0,
    status              TEXT NOT NULL CHECK (status IN ('running', 'success', 'partial', 'failed')),
    started_at          TEXT NOT NULL,
    finished_at         TEXT,
    checkpoint_block    INTEGER,
    error_text          TEXT
) STRICT;

CREATE TABLE discovery_queue (
    id                      TEXT PRIMARY KEY,
    chain_id                TEXT NOT NULL REFERENCES chain(id),
    address                 TEXT NOT NULL,
    runtime_code_hash       TEXT NOT NULL,
    tx_hash                 TEXT,
    deployer_address        TEXT,
    block_number            INTEGER,
    first_seen_at           TEXT NOT NULL,
    status                  TEXT NOT NULL CHECK (status IN ('new', 'triage', 'linked', 'ignored', 'quarantined')),
    suspected_template_id   TEXT REFERENCES template(id),
    classification          TEXT,
    risk_hint               TEXT CHECK (risk_hint IN ('low', 'medium', 'high', 'critical') OR risk_hint IS NULL),
    notes                   TEXT,
    resolved_by             TEXT REFERENCES person(id),
    resolved_at             TEXT,
    linked_instance_id      TEXT REFERENCES contract_instance(id),
    UNIQUE (chain_id, address)
) STRICT;

-- ---------------------------------------------------------------------------
-- 7. Tamper-evident operational audit trail
-- ---------------------------------------------------------------------------

CREATE TABLE audit_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    actor           TEXT NOT NULL,
    actor_type      TEXT NOT NULL CHECK (actor_type IN ('person', 'service', 'system')),
    action          TEXT NOT NULL,
    object_type     TEXT NOT NULL,
    object_id       TEXT NOT NULL,
    before_json     TEXT,
    after_json      TEXT,
    at              TEXT NOT NULL DEFAULT (datetime('now')),
    correlation_id  TEXT,
    source_ip       TEXT
) STRICT;

CREATE INDEX ix_audit_object ON audit_log(object_type, object_id, at);

-- ---------------------------------------------------------------------------
-- 8. Guardrails: segregation of duties and role eligibility
-- ---------------------------------------------------------------------------

CREATE TRIGGER trg_signoff_no_self_approval
BEFORE UPDATE OF decision ON signoff
WHEN NEW.decision = 'approved'
 AND NEW.decided_by IS NOT NULL
 AND NEW.object_type = 'deployment'
 AND NEW.decided_by = (SELECT requested_by FROM deployment_request WHERE id = NEW.object_id)
BEGIN
    SELECT RAISE(ABORT, 'SoD violation: requester cannot approve their own deployment');
END;

CREATE TRIGGER trg_signoff_no_self_approval_change
BEFORE UPDATE OF decision ON signoff
WHEN NEW.decision = 'approved'
 AND NEW.decided_by IS NOT NULL
 AND NEW.object_type = 'change'
 AND NEW.decided_by = (SELECT requested_by FROM change_request WHERE id = NEW.object_id)
BEGIN
    SELECT RAISE(ABORT, 'SoD violation: requester cannot approve their own change');
END;

CREATE TRIGGER trg_signoff_role_required
BEFORE UPDATE OF decision ON signoff
WHEN NEW.decision IN ('approved', 'rejected')
 AND NOT EXISTS (
    SELECT 1 FROM role_assignment ra
    WHERE ra.person_id = NEW.decided_by
      AND ra.role_code = NEW.required_role
      AND ra.active = 1
      AND (ra.valid_from IS NULL OR date(ra.valid_from) <= date('now'))
      AND (ra.valid_to IS NULL OR date(ra.valid_to) >= date('now'))
 )
BEGIN
    SELECT RAISE(ABORT, 'Actor does not hold the required active role');
END;

CREATE TRIGGER trg_signoff_one_person_per_object
BEFORE UPDATE OF decision ON signoff
WHEN NEW.decision = 'approved'
 AND NEW.decided_by IS NOT NULL
 AND EXISTS (
    SELECT 1 FROM signoff s
    WHERE s.object_type = NEW.object_type
      AND s.object_id = NEW.object_id
      AND s.decision = 'approved'
      AND s.decided_by = NEW.decided_by
      AND s.id <> NEW.id
 )
BEGIN
    SELECT RAISE(ABORT, 'Four-eyes violation: actor already approved another gate on this object');
END;

CREATE TRIGGER trg_audit_log_no_update
BEFORE UPDATE ON audit_log
BEGIN
    SELECT RAISE(ABORT, 'audit_log is append-only');
END;

CREATE TRIGGER trg_audit_log_no_delete
BEFORE DELETE ON audit_log
BEGIN
    SELECT RAISE(ABORT, 'audit_log is append-only');
END;
