-- Smart Contract Inventory & Control Registry
-- Combined SQLite source: schema, views, and seed data.
-- Rebuild: sqlite3 data/registry.db < registry.sql

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
    deployment_platform     TEXT NOT NULL DEFAULT 'Kaleido FireFly',
    signing_identity_id     TEXT REFERENCES signing_identity(id),
    evidence_json           TEXT,
    onboarding_source       TEXT,
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

-- ---------------------------------------------------------------------------
-- Read models
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Seed data
-- ---------------------------------------------------------------------------

-- Demo data: a Swiss-style digital assets estate, fictional names and addresses.
-- All hashes are deterministic demo values, not real bytecode.

INSERT INTO chain (id, name, caip2, chain_id, network_type, environment, consensus, privacy_mode, permissioning, rpc_endpoint, rpc_secret_ref, explorer_url, genesis_hash, finality_blocks, status) VALUES
('ch-eth-mainnet', 'Ethereum Mainnet', 'eip155:1', 1, 'public', 'PROD', 'Proof of Stake', 'none', 'public', 'https://eth-rpc.bank.internal/v1', 'vault/eth-rpc', 'https://etherscan.io', '0xa98343ccad8f547c2cc09d7a75f8c82242338e497342775cbcb4616871a9e60a', 64, 'active'),
('ch-besu-prod', 'Permissioned Ledger Production', 'eip155:42101', 42101, 'consortium', 'PROD', 'QBFT', 'Tessera private groups', 'validator + account allowlist', 'https://besu-prod.bank.internal:8545', 'vault/besu-prod-rpc', 'https://ledger-explorer.bank.internal', '0x2dfb52f83057166f27fb40c9c558e0932fc92e1f1ded03d227e758d142d14361', 2, 'active'),
('ch-besu-uat', 'Permissioned Ledger UAT', 'eip155:42102', 42102, 'consortium', 'UAT', 'QBFT', 'Tessera private groups', 'validator + account allowlist', 'https://besu-uat.bank.internal:8545', 'vault/besu-uat-rpc', 'https://ledger-uat-explorer.bank.internal', '0x9c89cc1dc87ad1156fba274035c51f0e51605d60b1e1602556c4d25f5ab389ed', 2, 'active');

INSERT INTO org_unit (id, code, name, parent_id, division, cost_center, legal_entity) VALUES
('org-gwm', 'GWM', 'Global Wealth Management', NULL, 'Global Wealth Management', 'CC-4100', 'Financial Institution AG'),
('org-gwm-da', 'GWM-DA', 'Digital Assets', 'org-gwm', 'Global Wealth Management', 'CC-4120', 'Financial Institution AG'),
('org-gwm-com', 'GWM-COM', 'Commodities', 'org-gwm', 'Global Wealth Management', 'CC-4130', 'Financial Institution AG'),
('org-gwm-lux', 'GWM-LUX', 'Digital Assets Luxembourg', 'org-gwm', 'Global Wealth Management', 'CC-4160', 'European Entity (Luxembourg) S.A.'),
('org-cio', 'CIO', 'Group Technology', NULL, 'Group Technology', 'CC-7000', 'Financial Institution AG'),
('org-cio-plt', 'CIO-PLT', 'Platform Engineering', 'org-cio', 'Group Technology', 'CC-7120', 'Financial Institution AG'),
('org-cio-sec', 'CIO-SEC', 'Cyber Security', 'org-cio', 'Group Technology', 'CC-7180', 'Financial Institution AG'),
('org-cro', 'CRO', 'Risk', NULL, 'Risk', 'CC-3000', 'Financial Institution AG'),
('org-cro-op', 'CRO-OP', 'Operational Risk', 'org-cro', 'Risk', 'CC-3210', 'Financial Institution AG'),
('org-cco', 'CCO', 'Compliance', NULL, 'Compliance', 'CC-2000', 'Financial Institution AG'),
('org-legal', 'LEGAL', 'Legal & Regulatory', NULL, 'Legal & Regulatory', 'CC-2100', 'Financial Institution AG'),
('org-fin', 'FIN', 'Finance', NULL, 'Finance', 'CC-1000', 'Financial Institution AG'),
('org-audit', 'AUDIT', 'Internal Audit', NULL, 'Internal Audit', 'CC-9000', 'Financial Institution AG');

INSERT INTO person (id, upn, display_name, email, title, org_unit_id, active) VALUES
('p-elena', 'elena.brunner@example.com', 'Elena Brunner', 'elena.brunner@example.com', 'Head Tokenized Commodities', 'org-gwm-com', 1),
('p-marco', 'marco.keller@example.com', 'Marco Keller', 'marco.keller@example.com', 'Product Owner, Digital Gold', 'org-gwm-da', 1),
('p-priya', 'priya.nair@example.com', 'Priya Nair', 'priya.nair@example.com', 'Solution Architect, Digital Assets', 'org-cio-plt', 1),
('p-sophie', 'sophie.meier@example.com', 'Sophie Meier', 'sophie.meier@example.com', 'Compliance Officer, Digital Assets', 'org-cco', 1),
('p-daniel', 'daniel.roth@example.com', 'Daniel Roth', 'daniel.roth@example.com', 'Legal Counsel, Capital Markets', 'org-legal', 1),
('p-andrea', 'andrea.vogel@example.com', 'Andrea Vogel', 'andrea.vogel@example.com', 'Operational Risk Manager', 'org-cro-op', 1),
('p-lucas', 'lucas.frei@example.com', 'Lucas Frei', 'lucas.frei@example.com', 'Smart Contract Security Lead', 'org-cio-sec', 1),
('p-nina', 'nina.baumann@example.com', 'Nina Baumann', 'nina.baumann@example.com', 'Platform Operations Lead', 'org-cio-plt', 1),
('p-reto', 'reto.graf@example.com', 'Reto Graf', 'reto.graf@example.com', 'Change Advisory Board Chair', 'org-cio', 1),
('p-claudia', 'claudia.hess@example.com', 'Claudia Hess', 'claudia.hess@example.com', 'Internal Audit Lead', 'org-audit', 1),
('p-jonas', 'jonas.weber@example.com', 'Jonas Weber', 'jonas.weber@example.com', 'Data Protection Officer', 'org-legal', 1),
('p-sara', 'sara.lang@example.com', 'Dr. Sara Lang', 'sara.lang@example.com', 'Model Risk Manager', 'org-cro', 1),
('p-luca', 'luca.bernardi@example.com', 'Luca Bernardi', 'luca.bernardi@example.com', 'Head Digital Assets Luxembourg', 'org-gwm-lux', 1),
('p-amelie', 'amelie.dubois@example.com', 'Amelie Dubois', 'amelie.dubois@example.com', 'Compliance Officer, Luxembourg', 'org-cco', 1);

INSERT INTO role_assignment (id, person_id, role_code, scope_org_unit_id, active, valid_from) VALUES
('ra-01', 'p-elena', 'Business Owner', 'org-gwm-com', 1, '2025-01-01'),
('ra-02', 'p-luca', 'Business Owner', 'org-gwm-lux', 1, '2025-06-01'),
('ra-03', 'p-marco', 'Product Owner', 'org-gwm', 1, '2025-01-01'),
('ra-04', 'p-luca', 'Product Owner', 'org-gwm-lux', 1, '2025-06-01'),
('ra-05', 'p-sophie', 'Compliance', NULL, 1, '2024-01-01'),
('ra-06', 'p-amelie', 'Compliance', 'org-gwm-lux', 1, '2025-06-01'),
('ra-07', 'p-daniel', 'Legal', NULL, 1, '2024-01-01'),
('ra-08', 'p-andrea', 'Operational Risk', NULL, 1, '2024-01-01'),
('ra-09', 'p-lucas', 'Security', NULL, 1, '2024-01-01'),
('ra-10', 'p-nina', 'Platform Operations', NULL, 1, '2024-01-01'),
('ra-11', 'p-reto', 'Change Advisory Board', NULL, 1, '2024-01-01'),
('ra-12', 'p-jonas', 'Data Protection', NULL, 1, '2024-01-01'),
('ra-13', 'p-sara', 'Model Risk', NULL, 1, '2024-01-01'),
('ra-14', 'p-claudia', 'Internal Audit', NULL, 1, '2024-01-01'),
('ra-15', 'p-priya', 'Platform Architect', NULL, 1, '2024-01-01'),
('ra-16', 'p-lucas', 'Template Owner', NULL, 1, '2024-01-01'),
('ra-17', 'p-marco', 'Business Owner', 'org-gwm-da', 1, '2025-01-01');

INSERT INTO signing_identity (id, name, key_type, provider, owner_person_id, allowlisted, valid_from, valid_to, last_used_at, evidence_uri) VALUES
('si-eth-service', 'Ethereum deployment service', 'hsm', 'Thales Luna HSM / CI OIDC', 'p-nina', 1, '2025-01-01', NULL, '2026-02-11', 'evidence://signers/si-eth-service'),
('si-besu-service', 'Besu production deployment service', 'hsm', 'Thales Luna HSM / CI OIDC', 'p-nina', 1, '2025-01-01', NULL, '2026-10-22', 'evidence://signers/si-besu-service'),
('si-besu-uat-service', 'Besu UAT deployment service', 'hsm', 'Thales Luna HSM / CI OIDC', 'p-nina', 1, '2025-01-01', NULL, '2026-10-22', 'evidence://signers/si-besu-uat-service'),
('si-safe-eth', 'Ethereum admin Safe 3-of-5', 'multisig', 'Safe', 'p-nina', 1, '2025-09-12', NULL, '2026-10-26', 'evidence://signers/si-safe-eth'),
('si-safe-besu', 'Ledger admin Safe 3-of-5', 'multisig', 'Safe', 'p-nina', 1, '2025-11-20', NULL, '2026-10-26', 'evidence://signers/si-safe-besu'),
('si-timelock-eth', 'Ethereum timelock 48h', 'timelock', 'OpenZeppelin TimelockController', 'p-nina', 1, '2025-09-12', NULL, '2026-10-26', 'evidence://signers/si-timelock-eth'),
('si-timelock-besu', 'Ledger timelock 48h', 'timelock', 'OpenZeppelin TimelockController', 'p-nina', 1, '2025-11-20', NULL, '2026-10-26', 'evidence://signers/si-timelock-besu'),
('si-old-besu', 'Legacy Besu deployer', 'eoa', 'Legacy service key', 'p-elena', 0, '2024-01-01', '2026-03-18', '2024-11-05', 'evidence://signers/si-old-besu'),
('si-chainlink', 'Chainlink feed operator', 'contract', 'Chainlink Labs', 'p-marco', 0, '2024-01-15', NULL, '2026-10-25', 'evidence://signers/si-chainlink');

INSERT INTO ict_third_party (id, name, lei, service, criticality, contract_ref, data_location, subcontractors, exit_plan, dora_register_ref, last_reviewed_at) VALUES
('ict-chainlink', 'Chainlink Labs', NULL, 'XAU/USD price feed and oracle operations', 'critical', 'CHAINLINK-2025-01', 'US / global', 'Decentralised node operators', 'Secondary feed plus manual LBMA valuation; pause minting if heartbeat fails.', 'DORA-ICT-014', '2026-10-20'),
('ict-besu', 'Ledger Consortium', NULL, 'Permissioned Besu network operation', 'critical', 'BESU-CONS-2024', 'CH', 'Validator operators', 'Migrate to alternate consortium or private chain; replay final state.', 'DORA-ICT-002', '2026-10-18'),
('ict-custodian', 'Precious Metals AG', NULL, 'Allocated gold custody and bar release', 'critical', 'CUST-2025-07', 'CH', 'Vault operator', 'Transfer allocated bars to alternate LBMA vault; legal title opinion required.', 'DORA-ICT-021', '2026-10-24'),
('ict-auditor', 'Helvetia Assurance AG', NULL, 'Reserve attestation and bar audit', 'high', 'AUD-2026-03', 'CH', 'None', 'Alternate attestation provider; retain last valid report during transition.', 'DORA-ICT-031', '2026-10-24'),
('ict-cloud', 'Private Cloud', NULL, 'Hosting, HSM and backup', 'critical', 'CLOUD-2024-11', 'CH', 'None', 'Failover to secondary Swiss region; tested annually.', 'DORA-ICT-001', '2026-10-01');

INSERT INTO persona (id, role_code, name, mandate, decision_rights, review_cadence, sort_order) VALUES
('per-business', 'BUSINESS', 'Business Owner / Product', 'Owns the commercial outcome, client proposition, product economics and adoption.', 'Accountable for product launch, pricing and client journey; cannot self-approve risk or compliance gates.', 'Monthly and per launch', 10),
('per-compliance', 'COMPLIANCE', 'Compliance / AML & Sanctions', 'Owns eligibility, AML/KYC, sanctions, travel rule, transfer restrictions and complaints.', 'Can block or condition a deployment; must evidence screening and client eligibility.', 'Per deployment and quarterly', 20),
('per-legal', 'LEGAL', 'Legal / Regulatory', 'Owns legal title, token classification, prospectus/terms, custody, cross-border and regulatory interpretation.', 'Can block or condition a deployment; signs legal opinion and terms.', 'Per deployment and annual', 30),
('per-risk', 'RISK', 'Operational Risk / Internal Audit', 'Owns control design, evidence, exceptions, incidents, DORA register and audit readiness.', 'Can block or condition a deployment; accepts residual risk within mandate.', 'Per deployment and quarterly', 40),
('per-security', 'SECURITY', 'CISO / Smart Contract Security', 'Owns key custody, deployer identity, upgrades, audit, monitoring and incident response.', 'Can block or condition a deployment; can invoke emergency pause.', 'Per deployment and continuous', 50),
('per-dpo', 'DPO', 'Data Protection / Privacy', 'Owns DPIA, PII boundaries, privacy groups, retention, DSAR and cross-border data.', 'Can block or condition a deployment; must approve public-chain or identity data.', 'Per deployment and annual', 60),
('per-finance', 'FINANCE', 'Finance / Treasury / Reserve', 'Owns reserve reconciliation, accounting, capital, tax, cost and chargeback.', 'Can block or condition a deployment; signs reserve and accounting treatment.', 'Monthly', 70),
('per-regulator', 'REGULATOR', 'Regulator / External Audit', 'Read-only challenge of evidence, register completeness, incident reporting and consumer outcomes.', 'No approval right; can require remediation or escalation.', 'On request and annual', 80);

INSERT INTO persona_finding (id, persona_id, object_type, object_id, severity, title, issue, recommendation, status, owner_person_id, accepted_by, due_date, expires_at, evidence_uri, created_at) VALUES
('pf-01', 'per-compliance', 'process', NULL, 'critical', 'Approvals are self-asserted in the demo', 'The approval API trusts an actor_id supplied by the browser; the demo has no IdP, session or MFA. A recorded Compliance approval is not evidence of who approved.', 'Bind approvals to an OIDC subject, MFA/auth_time and server-side session; remove the actor selector; store IdP assertion; mark demo mode explicitly.', 'open', 'p-nina', NULL, '2027-01-31', NULL, 'evidence://council/pf-01', '2026-10-26T09:00:00Z'),
('pf-02', 'per-legal', 'deployment_request', 'DR-2026-0031', 'critical', 'Legal gate has no signed document hash', 'DR-2026-0031 LEGAL approval uses a placeholder evidence URI and no evidence hash or document link; the legal opinion is not traceable to the approval.', 'Require a document_id and SHA-256 evidence hash for LEGAL and COMPLIANCE gates; block approval without it; add expiry and legal-hold fields.', 'open', 'p-daniel', NULL, '2027-01-15', NULL, 'evidence://council/pf-02', '2026-10-26T09:05:00Z'),
('pf-03', 'per-compliance', 'contract', 'ci-ubgx-eth', 'high', 'Public token restrictions are not linked to the rule engine', 'The public UBGX initializer points to the Besu RuleEngine, but the public instance has no uses_rule_engine or identity-registry link. Transfer restrictions may not bind mainnet.', 'Add mandatory token -> rule-engine/identity/oracle/reserve links; store rule-set version; block readiness if a public token lacks a rule-engine link or transfer test.', 'open', 'p-sophie', NULL, '2026-12-15', NULL, 'evidence://council/pf-03', '2026-10-26T09:10:00Z'),
('pf-04', 'per-legal', 'contract', 'ci-ubgx-eth', 'high', 'Legal title and insolvency remoteness are not in the register', 'Reserve pools record custodian and vault but not the trust/segregation basis, holder claim type, governing law, custody agreement or insolvency opinion.', 'Add legal_structure, holder_claim_type, segregation_basis, insolvency_remoteness and custody agreement reference to the compliance profile; link the legal opinion.', 'open', 'p-daniel', NULL, '2027-02-28', NULL, 'evidence://council/pf-04', '2026-10-26T09:15:00Z'),
('pf-05', 'per-risk', 'process', NULL, 'high', 'DORA scope covers only one public token', 'The DORA evidence is attached to ci-ubgx-eth only; the ledger token, DvP, custody provider and Chainlink feed are not all represented in a third-party register.', 'Add an ICT third-party register linked to instances, with criticality, contract, data location, exit plan and DORA reference; make SC-09 depend on it.', 'open', 'p-andrea', NULL, '2027-01-31', NULL, 'evidence://council/pf-05', '2026-10-26T09:20:00Z'),
('pf-06', 'per-security', 'process', NULL, 'high', 'Deployer identity and key custody are not modelled', 'Instances store an address but not the HSM/CI identity, allowlist status or rotation; an unallowlisted EOA deployed unknown Besu contracts.', 'Add signing identities with key type, provider, allowlist and validity; link every instance; block non-allowlisted production deployers; show signer in the UI.', 'remediated', 'p-lucas', NULL, '2026-12-31', NULL, 'evidence://council/pf-06', '2026-10-26T09:25:00Z'),
('pf-07', 'per-security', 'contract', 'ci-ubgx-eth', 'high', 'Upgrade governance is recorded but not proven', 'CR-2026-004 claims a 2.9.0 to 3.0.0 upgrade without a previous implementation record, timelock delay proof or storage-layout evidence.', 'Add upgrade history with from/to implementation, timelock transaction, delay, layout hash and change request; verify getMinDelay() and Upgraded logs; show unverified badge.', 'open', 'p-lucas', NULL, '2026-12-31', NULL, 'evidence://council/pf-07', '2026-10-26T09:30:00Z'),
('pf-08', 'per-dpo', 'contract', 'ci-ubgx-eth', 'high', 'No DPIA is linked to the public gold token', 'The public token exposes addresses, supply and document URIs; no DPIA, ROPA entry or public-chain data assessment is linked.', 'Add dpia_ref and dpo_assessment to the compliance profile; require DPO gate for public-chain and identity contracts regardless of risk tier.', 'open', 'p-jonas', NULL, '2027-01-31', NULL, 'evidence://council/pf-08', '2026-10-26T09:35:00Z'),
('pf-09', 'per-dpo', 'contract', 'ci-ubgx-besu', 'high', 'Privacy-group membership is not recorded', 'The privacy group is a free-text label with no member list, jurisdictions, data categories or private/marker transaction hashes.', 'Add privacy-group members and transaction hashes; show members in the contract modal; require DPO approval before adding a participant.', 'open', 'p-jonas', NULL, '2027-02-28', NULL, 'evidence://council/pf-09', '2026-10-26T09:40:00Z'),
('pf-10', 'per-finance', 'contract', 'ci-ubgx-eth', 'high', 'Bar list does not reconcile to the reserve snapshot', 'The public snapshot says 8 bars / 93,425g but only 4 bars / 50,000g were listed; the ledger snapshot had 3 bars / 37,500g vs 32,825g.', 'Derive coverage from the summed bar list and on-chain totalSupply; add a reconciliation view and test; publish the complete bar-list hash.', 'remediated', 'p-elena', NULL, '2026-11-30', NULL, 'evidence://council/pf-10', '2026-10-26T09:45:00Z'),
('pf-11', 'per-risk', 'template', 'tpl-dvp-100', 'high', 'Critical template approved without template gates', 'tpl-dvp-100 and tpl-collateral-100 were marked approved with zero template sign-offs.', 'Generate template gates for every approved high/critical template; require them before readiness; add a negative test.', 'remediated', 'p-andrea', NULL, '2026-11-30', NULL, 'evidence://council/pf-11', '2026-10-26T09:50:00Z'),
('pf-12', 'per-risk', 'process', NULL, 'high', 'Approval evidence is a placeholder', 'Approved gates use evidence:// URIs, evidence_hash is often null and document links are missing; the audit trail is mutable SQLite.', 'Add evidence gap view and council KPI; require document/hash for future approvals; make audit_log append-only and plan WORM/hash chain for production.', 'open', 'p-andrea', NULL, '2027-01-31', NULL, 'evidence://council/pf-12', '2026-10-26T09:55:00Z'),
('pf-13', 'per-business', 'contract', 'ci-ubgx-eth', 'medium', 'Redemption journey is not represented', 'The token has redemption terms but no request, queue, SLA, fees, burn/bar release or client trust page.', 'Add redemption request data, TAT p50/p95, buffer and fee fields; show a client-facing reserve/redemption status in the product view.', 'open', 'p-marco', NULL, '2027-03-31', NULL, 'evidence://council/pf-13', '2026-10-26T10:00:00Z'),
('pf-14', 'per-finance', 'process', NULL, 'medium', 'Revenue attribution in the business case is not Finance-approved', 'The base case attributes 50% of one incremental product launch to the registry; Finance has not approved the method.', 'Split cash vs non-cash benefits; show a control-only case; get Finance attribution or drop revenue from the base case; add ramp and sensitivity.', 'open', 'p-elena', NULL, '2026-12-15', NULL, 'evidence://council/pf-14', '2026-10-26T10:05:00Z'),
('pf-15', 'per-compliance', 'process', NULL, 'medium', 'No complaints or redress record', 'A client refused by the country rule or holder cap has no complaint, appeal or ombudsman path in the register.', 'Add complaint/redress fields and a queue; record category, outcome, redress and ageing; link to the product instance.', 'open', 'p-sophie', NULL, '2027-03-31', NULL, 'evidence://council/pf-15', '2026-10-26T10:10:00Z'),
('pf-16', 'per-security', 'incident', 'disc-003', 'medium', 'Unknown clone is quarantined but not incident-linked', 'disc-003 is a 94% CMTAT clone on Ethereum mainnet, quarantined as critical, but no incident record or blocklist evidence exists.', 'Create an incident automatically on quarantine; require owner, containment, blocklist evidence and DORA reporting decision.', 'open', 'p-lucas', NULL, '2026-11-15', NULL, 'evidence://council/pf-16', '2026-10-26T10:15:00Z'),
('pf-17', 'per-dpo', 'process', NULL, 'medium', 'Retention and DSAR handling are incomplete', 'Only documents have retention_until; signoff comments, audit log payloads and onchain event payloads lack retention class, legal hold and DSAR scoping.', 'Add retention_policy, legal_hold and data_subject_request; hash/screen free-text comments; restrict audit payloads; enforce is_sensitive.', 'open', 'p-jonas', NULL, '2027-06-30', NULL, 'evidence://council/pf-17', '2026-10-26T10:20:00Z'),
('pf-18', 'per-risk', 'deployment_request', 'DR-2026-0051', 'low', 'One person can hold two blocking roles', 'Role assignments allow the same person to be Business Owner and Product Owner; the demo approval does not prevent one person approving two gates on the same object.', 'Add a four-eyes check: one person may approve only one blocking gate per object; test it in the database and API.', 'remediated', 'p-reto', NULL, '2026-11-30', NULL, 'evidence://council/pf-18', '2026-10-26T10:25:00Z'),
('pf-19', 'per-legal', 'contract', 'ci-ubgx-besu', 'high', 'Public and ledger tokens share an ISIN but have separate pools', 'ci-ubgx-eth and ci-ubgx-besu share ISIN CH0000000001 and symbol UBGX while using separate reserve pools; fungibility and disclosure are unclear.', 'Add instrument_id and fungibility_group; document whether the ledger token is a mirror, a separate security or a receipt; reconcile supply across pools.', 'open', 'p-daniel', NULL, '2027-01-31', NULL, 'evidence://council/pf-19', '2026-10-26T10:30:00Z'),
('pf-20', 'per-compliance', 'process', NULL, 'high', 'Sanctions and travel-rule evidence is asserted', 'Compliance gates say sanctions and travel rule are approved, but there is no screening result, list version, disposition or VASP/travel-rule payload.', 'Add screening and transfer records; store list version, result, disposition and VASP data; add controls and evidence checks.', 'open', 'p-sophie', NULL, '2027-01-31', NULL, 'evidence://council/pf-20', '2026-10-26T10:35:00Z');

INSERT INTO standard (code, name, family, url, status) VALUES
('ERC-20', 'Fungible Token Standard', 'token', 'https://eips.ethereum.org/EIPS/eip-20', 'final'),
('ERC-165', 'Standard Interface Detection', 'interface', 'https://eips.ethereum.org/EIPS/eip-165', 'final'),
('ERC-173', 'Contract Ownership Standard', 'interface', 'https://eips.ethereum.org/EIPS/eip-173', 'final'),
('ERC-721', 'Non-Fungible Token Standard', 'token', 'https://eips.ethereum.org/EIPS/eip-721', 'final'),
('ERC-1155', 'Multi-Token Standard', 'token', 'https://eips.ethereum.org/EIPS/eip-1155', 'final'),
('ERC-1271', 'Standard Signature Validation Method for Contracts', 'account', 'https://eips.ethereum.org/EIPS/eip-1271', 'final'),
('ERC-1400', 'Security Token Standard', 'security', 'https://eips.ethereum.org/EIPS/eip-1400', 'draft'),
('ERC-1404', 'Simple Restricted Token Standard', 'security', 'https://github.com/ethereum/EIPs/issues/1404', 'draft'),
('ERC-1643', 'Document Management Standard', 'security', 'https://github.com/ethereum/EIPs/issues/1643', 'draft'),
('ERC-1822', 'Universal Upgradeable Proxy Standard', 'proxy', 'https://eips.ethereum.org/EIPS/eip-1822', 'final'),
('ERC-1967', 'Proxy Storage Slots', 'proxy', 'https://eips.ethereum.org/EIPS/eip-1967', 'final'),
('ERC-1167', 'Minimal Proxy Contract', 'proxy', 'https://eips.ethereum.org/EIPS/eip-1167', 'final'),
('ERC-1014', 'Deterministic Address Creation (CREATE2)', 'deployment', 'https://eips.ethereum.org/EIPS/eip-1014', 'final'),
('ERC-2612', 'Permit Extension for EIP-20', 'token', 'https://eips.ethereum.org/EIPS/eip-2612', 'final'),
('ERC-2771', 'Secure Protocol for Native Meta-Transactions', 'account', 'https://eips.ethereum.org/EIPS/eip-2771', 'final'),
('ERC-3643', 'T-REX Permissioned Security Token', 'security', 'https://eips.ethereum.org/EIPS/eip-3643', 'final'),
('ERC-4337', 'Account Abstraction Using Alt Mempool', 'account', 'https://eips.ethereum.org/EIPS/eip-4337', 'final'),
('ERC-4626', 'Tokenized Vault Standard', 'token', 'https://eips.ethereum.org/EIPS/eip-4626', 'final'),
('ERC-7579', 'Modular Smart Accounts', 'account', 'https://eips.ethereum.org/EIPS/eip-7579', 'final'),
('ERC-7802', 'Cross-Chain Mint/Burn Interface', 'interop', 'https://eips.ethereum.org/EIPS/eip-7802', 'final'),
('ERC-2535', 'Diamond Standard', 'proxy', 'https://eips.ethereum.org/EIPS/eip-2535', 'final'),
('ERC-3525', 'Semi-Fungible Token', 'token', 'https://eips.ethereum.org/EIPS/eip-3525', 'final'),
('ERC-7201', 'Namespaced Storage Layout', 'proxy', 'https://eips.ethereum.org/EIPS/eip-7201', 'final'),
('CMTAT', 'CMTA Token Framework', 'security', 'https://github.com/CMTA/CMTAT', 'final'),
('CMTAT-RULE-ENGINE', 'CMTA Rule Engine', 'compliance', 'https://github.com/CMTA/RuleEngine', 'final'),
('CMTAT-DVP', 'CMTA Delivery versus Payment', 'settlement', 'https://github.com/CMTA/DVP', 'final'),
('ONCHAINID', 'On-chain Identity and Claims', 'identity', 'https://github.com/onchain-id/solidity', 'final'),
('EEA-ETHTRUST', 'EEA EthTrust Security Levels', 'assurance', 'https://entethalliance.org/specs/ethtrust-sl/', 'final'),
('LBMA-GOOD-DELIVERY', 'LBMA Good Delivery Rules', 'commodity', 'https://www.lbma.org.uk/good-delivery', 'final'),
('ISO-4217', 'Currency Codes', 'data', 'https://www.iso.org/iso-4217-currency-codes.html', 'final'),
('ISO-3166', 'Country Codes', 'data', 'https://www.iso.org/iso-3166-country-codes.html', 'final'),
('GNOSIS-SAFE', 'Safe Multisig', 'account', 'https://safe.global', 'final'),
('CHAINLINK-CCIP', 'Cross-Chain Interoperability Protocol', 'interop', 'https://chain.link/ccip', 'final'),
('CHAINLINK-AGGREGATOR-V3', 'Chainlink Aggregator V3 Interface', 'oracle', 'https://docs.chain.link/data-feeds', 'final'),
('MULTICALL3', 'Multicall3', 'utility', 'https://github.com/mds1/multicall', 'final'),
('OPENZEPPELIN-TIMELOCK', 'OpenZeppelin TimelockController', 'governance', 'https://docs.openzeppelin.com/contracts/5.x/api/governance', 'final'),
('DORA-REGISTER', 'DORA Register of Information', 'regulatory', 'https://www.eiopa.europa.eu/digital-operational-resilience-act-dora_en', 'final'),
('GROTH16-VERIFIER', 'Groth16 Verifier', 'privacy', 'https://docs.zkproof.org', 'final'),
('ATTESTATION-REGISTRY', 'On-chain Attestation Registry', 'attestation', 'https://attest.sh', 'final'),
('CUSTOM-ESCROW', 'Internal Escrow Pattern', 'settlement', 'https://git.bank.internal/escrow', 'internal');

INSERT INTO template (id, template_key, name, version, category, contract_type, description, source_repo, source_path, git_commit, compiler_version, evm_version, license, initcode_hash, runtime_code_hash, abi_hash, audit_status, audit_provider, audit_valid_until, ethtrust_level, default_risk_tier, owner_org_unit_id, status, approved_at, retired_at, created_at, notes) VALUES
('tpl-cmtat-230', 'CMTAT_STANDARD', 'CMTAT Standard', '2.3.0', 'token', 'CMTAT', 'Audited predecessor used by the legacy gold token. Retired from new deployments.', 'https://github.com/CMTA/CMTAT', 'contracts/CMTAT.sol', '0x0c3ca99e44c2d30fb224ef0e66db477cd1c961cdc19adc62814cc72c7f6fcf64', '0.8.17', 'paris', 'MPL-2.0', '0xd695bd11dfc544bff305682566d68e43bb727a000c8bb1b5bbe1bc1e0cc0ee47', '0xd695bd11dfc544bff305682566d68e43bb727a000c8bb1b5bbe1bc1e0cc0ee47', '0x3ba3c3084835f811f49c0af749f8239e56e4c4d4270413af57cf54c5ebeeed11', 'external', 'ABDK', '2025-12-31', NULL, 'high', 'org-gwm-da', 'deprecated', '2024-06-01', '2026-03-18', '2024-04-10', 'No new deployments after the March 2026 migration.'),
('tpl-cmtat-300', 'CMTAT_STANDARD', 'CMTAT Standard', '3.0.0', 'token', 'CMTAT', 'Regulated security-token framework used for tokenized gold. Flagship, externally audited release.', 'https://github.com/CMTA/CMTAT', 'contracts/CMTAT.sol', '0x98f1ef0cc5778f061398d502b7c2f016d4f2a21e2544c1d5dd2b35b9210f049d', '0.8.24', 'shanghai', 'MPL-2.0', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '0x3ba3c3084835f811f49c0af749f8239e56e4c4d4270413af57cf54c5ebeeed11', 'external', 'Halborn', '2026-12-15', NULL, 'high', 'org-gwm-da', 'approved', '2024-10-15', NULL, '2024-09-20', 'Audit renewal due before 2026-12-15.'),
('tpl-cmtat-320', 'CMTAT_STANDARD', 'CMTAT Standard', '3.2.0', 'token', 'CMTAT', 'Newer CMTAT release. Self-assessed only; not eligible for high-risk production deployment.', 'https://github.com/CMTA/CMTAT', 'contracts/CMTAT.sol', '0xc371e0ec4b8af378bf2bbcdd200ad1985ea70d1a136e5c810710633efb0f5fc2', '0.8.26', 'cancun', 'MPL-2.0', '0xd07cca96547e064345cc59ef581e00cf9b9ab065db9dc0ed76c747be31fa0a05', '0xd07cca96547e064345cc59ef581e00cf9b9ab065db9dc0ed76c747be31fa0a05', '0x3ba3c3084835f811f49c0af749f8239e56e4c4d4270413af57cf54c5ebeeed11', 'self', 'Internal security review', '2026-10-01', NULL, 'high', 'org-gwm-da', 'draft', NULL, NULL, '2026-08-01', 'Blocked for high/critical risk until an independent audit is completed.'),
('tpl-cmtat-uups-300', 'CMTAT_UUPS', 'CMTAT UUPS', '3.0.0', 'token', 'CMTAT UUPS', 'Upgradeable CMTAT behind an ERC-1967 UUPS proxy. Used for the public gold token.', 'https://github.com/CMTA/CMTAT', 'contracts/CMTATUpgradeableUUPS.sol', '0xe3ce15b299a2713675fc2a76f444a766e24e0b13020376ff1d7c6df68e166f99', '0.8.24', 'shanghai', 'MPL-2.0', '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b', '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b', '0x57fdbc206dfed6ce9f776457c08226f7aa4afaac72bdde5d6072f2c37289a3f3', 'external', 'Halborn', '2026-12-15', NULL, 'critical', 'org-gwm-da', 'approved', '2024-10-15', NULL, '2024-09-20', 'Upgrade authority must be a timelock, never an EOA.'),
('tpl-ruleengine-100', 'CMTAT_RULE_ENGINE', 'CMTA Rule Engine', '1.0.0', 'compliance', 'RuleEngine', 'External rule controller invoked by CMTAT before every transfer.', 'https://github.com/CMTA/RuleEngine', 'contracts/RuleEngine.sol', '0x08825bbbfec968d79204e8a6d869ab6649177ad9746c2f3b0d315da3d0dd80f6', '0.8.24', 'shanghai', 'MPL-2.0', '0xd53314af8045b38c8c31ba55894b96f36e78f136ccdfe056c85d33e2005737b1', '0xd53314af8045b38c8c31ba55894b96f36e78f136ccdfe056c85d33e2005737b1', '0x304a9ed3a3dac5d60ab5a3145b118799756bb5de336ab4cec4284157c4594fd3', 'external', 'ChainSecurity', '2027-03-31', NULL, 'high', 'org-cco', 'approved', '2025-02-10', NULL, '2025-01-15', 'Rule changes are high-risk changes and require Compliance, Risk, Security and CAB.'),
('tpl-rule-maxholders-110', 'RULE_MAX_HOLDERS', 'Rule: Maximum Holders', '1.1.0', 'compliance', 'Rule', 'Caps the number of token holders for distribution-control purposes.', 'https://github.com/CMTA/Rules', 'contracts/RuleMaxHolders.sol', '0xb4f2576fab7530ce2d025b1b866c203d4b8a2248dc9cccacdccb47de036a2670', '0.8.24', 'shanghai', 'MPL-2.0', '0x7ef6e2e40660aeb0e1b76cf8b4a40695450e429d279595bdbd9abd12b4bbccbd', '0x7ef6e2e40660aeb0e1b76cf8b4a40695450e429d279595bdbd9abd12b4bbccbd', '0x304a9ed3a3dac5d60ab5a3145b118799756bb5de336ab4cec4284157c4594fd3', 'internal', 'Group Security', '2027-01-31', NULL, 'high', 'org-cco', 'approved', '2025-02-10', NULL, '2025-01-15', 'Internal audit accepted for this narrow rule.'),
('tpl-rule-country-100', 'RULE_COUNTRY_RESTRICTION', 'Rule: Country Restriction', '1.0.0', 'compliance', 'Rule', 'Restricts transfers to approved investor jurisdictions.', 'https://github.com/CMTA/Rules', 'contracts/RuleCountryRestriction.sol', '0xfd54e3797e3c257ea32ced33d1ab9774015a7d1841b9436f655c36787e14510e', '0.8.24', 'shanghai', 'MPL-2.0', '0x128b8939927502564ec244e479df22e6d577f35ce1dc3ab7ef91ba395b68059f', '0x128b8939927502564ec244e479df22e6d577f35ce1dc3ab7ef91ba395b68059f', '0x304a9ed3a3dac5d60ab5a3145b118799756bb5de336ab4cec4284157c4594fd3', 'internal', 'Group Security', '2027-01-31', NULL, 'high', 'org-cco', 'approved', '2025-02-10', NULL, '2025-01-15', 'Admin must remain under Safe control; see control exception CTL-05.'),
('tpl-identity-100', 'ERC3643_IDENTITY_REGISTRY', 'ERC-3643 Identity Registry', '1.0.0', 'identity', 'IdentityRegistry', 'Maps investor wallets to ONCHAINID identities and verification status.', 'https://github.com/onchain-id/solidity', 'contracts/IdentityRegistry.sol', '0x1b7f5f9ae1f06b59b74aca7a26c971e68c12dbab999f103622e9d4d9b6f5a51a', '0.8.24', 'shanghai', 'Apache-2.0', '0x5173d7005e3e33a181eaa72807d1adb9edd1c03d1ff3ee4f15518ea402b7c02f', '0x5173d7005e3e33a181eaa72807d1adb9edd1c03d1ff3ee4f15518ea402b7c02f', '0xcf5f749200b0ecead34ee1ca5f0d0e54503644d756b22503ce28c7960fd1ce9c', 'external', 'Hacken', '2027-06-30', NULL, 'high', 'org-cco', 'approved', '2025-02-10', NULL, '2025-01-15', 'Holds personal data references only; no PII on-chain.'),
('tpl-trusted-100', 'ERC3643_TRUSTED_ISSUERS', 'ERC-3643 Trusted Issuers Registry', '1.0.0', 'identity', 'TrustedIssuersRegistry', 'Registry of claim issuers trusted by the identity registry.', 'https://github.com/onchain-id/solidity', 'contracts/TrustedIssuersRegistry.sol', '0x20d7d98dffd5d87a5154a0b293e8679ddc1053ff602d8c6c5674da04259e79f0', '0.8.24', 'shanghai', 'Apache-2.0', '0x3b9710f8a4959f31b7d132812b624066d21d57f8a23f27770c2cba0b46b395f5', '0x3b9710f8a4959f31b7d132812b624066d21d57f8a23f27770c2cba0b46b395f5', '0x5b01ccbd562f1e3c01c12eccc5e8b4bfbadcbe3aafa222d7a339fe9bef386f48', 'external', 'Hacken', '2027-06-30', NULL, 'high', 'org-cco', 'approved', '2025-02-10', NULL, '2025-01-15', NULL),
('tpl-claim-100', 'ERC3643_CLAIM_TOPICS', 'ERC-3643 Claim Topics Registry', '1.0.0', 'identity', 'ClaimTopicsRegistry', 'Defines the claim topics required for an investor to hold the token.', 'https://github.com/onchain-id/solidity', 'contracts/ClaimTopicsRegistry.sol', '0x1b1c72d74a4abc0c58634261c6907a8520ad4a66fa6f0a057be8091d8f5aac1d', '0.8.24', 'shanghai', 'Apache-2.0', '0x170aabb7129ffc6fe7a39c1fb766e8a6ec8d38fd8ebcf2d2e1208c973accfbd5', '0x170aabb7129ffc6fe7a39c1fb766e8a6ec8d38fd8ebcf2d2e1208c973accfbd5', '0x67e346ad60f70b440f606c4e1ee578c0d0f82356c866249d88da8f7ee95aa86f', 'external', 'Hacken', '2027-06-30', NULL, 'medium', 'org-cco', 'approved', '2025-02-10', NULL, '2025-01-15', NULL),
('tpl-dvp-100', 'CMTAT_DVP', 'CMTA Delivery versus Payment', '1.0.0', 'settlement', 'DvP', 'Atomic delivery-versus-payment settlement between an asset token and a cash token.', 'https://github.com/CMTA/DVP', 'contracts/DVP.sol', '0xf856c38044347edaba1bae72f95fdcd9d7accf2f88eaa7c377eb43208c78b909', '0.8.24', 'shanghai', 'MPL-2.0', '0x21ce350fcb275bcca4a2168b70c7a8f6ec6598c948714e3f0b3278b119648716', '0x21ce350fcb275bcca4a2168b70c7a8f6ec6598c948714e3f0b3278b119648716', '0x8664035eb6c0fad001fcfaadedcdaea89978a9745a7f84098d413927c899a28a', 'external', 'Halborn', '2027-03-31', NULL, 'critical', 'org-gwm-da', 'approved', '2025-05-20', NULL, '2025-04-01', 'Settlement finality and payment-leg failure are critical risks.'),
('tpl-escrow-120', 'ESCROW', 'Escrow', '1.2.0', 'value', 'Escrow', 'Conditional value-holding contract for bilateral trades and collateral arrangements.', 'https://git.bank.internal/sc/escrow', 'contracts/Escrow.sol', '0x6694bc458501f3d802b4eba5904fb59a9edfa246eb5ab386ee07b18b5f236818', '0.8.24', 'shanghai', 'Internal', '0x334e84885b851c05dd1f7eebdd340b78c3f5dd8e3d140fa762596f77c70cec89', '0x334e84885b851c05dd1f7eebdd340b78c3f5dd8e3d140fa762596f77c70cec89', '0x4c30138e427b9330bfc72240d5e8ec2211abe53e20fe476219998089a4f5d50e', 'internal', 'Group Security', '2027-02-28', NULL, 'high', 'org-gwm-da', 'approved', '2025-08-15', NULL, '2025-07-01', NULL),
('tpl-erc4626-100', 'ERC4626_VAULT', 'ERC-4626 Tokenized Vault', '1.0.0', 'value', 'TokenizedVault', 'Yield-bearing vault wrapper for money-market fund units.', 'https://github.com/OpenZeppelin/openzeppelin-contracts', 'contracts/token/ERC20/extensions/ERC4626.sol', '0xcb76bc8b152bed8695d949d913cc86b3c93ac72166f45a90fb8d92d3920f9130', '0.8.24', 'shanghai', 'MIT', '0x1bffd783d0ac97edd0ddc20315c8ac9aae890b5cfd5a27c12d7072b58fe98146', '0x1bffd783d0ac97edd0ddc20315c8ac9aae890b5cfd5a27c12d7072b58fe98146', NULL, 'external', 'OpenZeppelin', '2027-04-30', NULL, 'high', 'org-gwm-da', 'approved', '2025-09-01', NULL, '2025-08-01', 'Taxonomy covers value-bearing vaults even where no live instance exists.'),
('tpl-multicall-300', 'MULTICALL3', 'Multicall3', '3.0.0', 'utility', 'Utility', 'Batches multiple read or write calls in one transaction. Low-risk shared utility.', 'https://github.com/mds1/multicall', 'src/Multicall3.sol', '0xba4e06e4731f0217be6bc703689ec78e5c209ee27b72c1cc7fec43fb70c00081', '0.8.19', 'paris', 'MIT', '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30', '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30', '0xeb5e0c8c8566fbc16652783cbe7a1e456b2d9635ef97b6947916965d4e4d774b', 'self', 'Canonical public utility', NULL, NULL, 'low', 'org-cio-plt', 'approved', '2025-06-01', NULL, '2025-05-20', 'No privileged roles and no value custody.'),
('tpl-factory-100', 'CMTAT_FACTORY', 'CMTAT Factory', '1.0.0', 'factory', 'Factory', 'Deploys CMTAT proxies and clones at deterministic CREATE2 addresses.', 'https://github.com/CMTA/CMTAT-Factory', 'contracts/CMTATFactory.sol', '0x4ce6fa9b6ceb6e657bc20e19192eb7c99b31b33d76609407549373cf1186196a', '0.8.24', 'shanghai', 'MPL-2.0', '0x8bd8d766ca3e3eb5864d9b1323192e21ff3c88ed582d91f5977c6447601ea363', '0x8bd8d766ca3e3eb5864d9b1323192e21ff3c88ed582d91f5977c6447601ea363', '0x6582b0efac40213007c4deb6be30921b0355e306b754b16951b69ded41c1106d', 'external', 'ABDK', '2027-05-31', NULL, 'high', 'org-cio-plt', 'approved', '2025-06-10', NULL, '2025-05-01', 'Factory allowlist is part of the deployment control.'),
('tpl-proxy-100', 'ERC1967_PROXY', 'ERC-1967 Proxy', '1.0.0', 'proxy', 'Proxy', 'Transparent/UUPS proxy with standard implementation, admin and beacon slots.', 'https://github.com/OpenZeppelin/openzeppelin-contracts', 'contracts/proxy/ERC1967/ERC1967Proxy.sol', '0x339a8c40555b82d12c4a0d496ec996e4cd11c4e84fe8a874d89d7e2024d99e42', '0.8.24', 'shanghai', 'MIT', '0x499b260f022058eb6d8480b2ea87fddd723fa0e4c5f70fa6b2cb41f1e2efd2b0', '0x499b260f022058eb6d8480b2ea87fddd723fa0e4c5f70fa6b2cb41f1e2efd2b0', '0x1574bf2076f4352c9a9b1fed32e28cef2a0c2aeb8de062e3d536fd1364d147c9', 'external', 'OpenZeppelin', '2027-04-30', NULL, 'medium', 'org-cio-plt', 'approved', '2025-06-10', NULL, '2025-05-01', 'Proxy detection uses EIP-1967 slots.'),
('tpl-oracle-100', 'GOLD_PRICE_ORACLE_ADAPTER', 'Gold Price Oracle Adapter', '1.0.0', 'oracle', 'OracleAdapter', 'Validates and normalises a Chainlink XAU/USD feed for the gold token.', 'https://git.bank.internal/sc/gold-oracle', 'contracts/GoldPriceOracleAdapter.sol', '0xc449a41f4f36dcb38e6428209778435db7b96096abe421ef591a1a58167ed9fc', '0.8.24', 'shanghai', 'Internal', '0xa74513cfec7f6f1618d4b0484e7ae90725adf1c49874d8ac138be21255d28282', '0xa74513cfec7f6f1618d4b0484e7ae90725adf1c49874d8ac138be21255d28282', '0x85ded5ed4004e6e10fbd38638bd8f163372c00ca52126d7049171dc4037e6f3f', 'external', 'Nethermind', '2027-02-28', NULL, 'high', 'org-gwm-da', 'approved', '2025-07-01', NULL, '2025-06-01', 'Stale-price and deviation checks are mandatory.'),
('tpl-timelock-100', 'TIMELOCK_CONTROLLER', 'Timelock Controller', '1.0.0', 'governance', 'Timelock', 'Delays privileged operations and enforces multi-party execution.', 'https://github.com/OpenZeppelin/openzeppelin-contracts', 'contracts/governance/TimelockController.sol', '0x3308556c49da98fcd9c05a185e0d43d4e6305976d312c7a61d6ac71822907f76', '0.8.24', 'shanghai', 'MIT', '0x62987977408a6e2a1cda748337bce75ad75b02110c5e2691ec9fc8c2f7e70afb', '0x62987977408a6e2a1cda748337bce75ad75b02110c5e2691ec9fc8c2f7e70afb', '0x7643ab53b98daca947957eb1d62486decf5aa092c2a8a0029f40765bff85622e', 'external', 'OpenZeppelin', '2027-04-30', NULL, 'high', 'org-cio-plt', 'approved', '2025-06-10', NULL, '2025-05-01', 'Minimum delay 48h for production admin actions.'),
('tpl-safe-140', 'SAFE_MULTISIG', 'Safe Multisig', '1.4.0', 'account', 'Multisig', '3-of-5 institutional multisig for admin and treasury roles.', 'https://github.com/safe-global/safe-smart-account', 'contracts/Safe.sol', '0x05f710eb3b0ee18e9a0d54a0e80356518c50f9e578bc15b6c06f0b8637a0c713', '0.8.24', 'shanghai', 'LGPL-3.0', '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4', '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4', '0x892d124da3fca73853ead3776e351dde1231e9aee68caa35cdf2ffed492642c2', 'external', 'Ackee Blockchain', '2027-06-30', NULL, 'high', 'org-cio-plt', 'approved', '2025-06-10', NULL, '2025-05-01', 'Signer keys are HSM-backed; no single EOAs.'),
('tpl-ccip-100', 'CCIP_TOKEN_ADAPTER', 'CCIP Token Adapter', '1.0.0', 'interop', 'BridgeAdapter', 'Mint/burn bridge adapter for a cross-chain representation. Not approved for production.', 'https://github.com/smartcontractkit/ccip', 'contracts/CCIPAdapter.sol', '0xeb59ecf7219b1ff37aa014d7134d99e53dc1c6abfa518ff41755c49815104786', '0.8.24', 'shanghai', 'MIT', '0x8c0f900218ba7c4022e44f2993df59d56d5b15887572f4d4aa3774072784d450', '0x8c0f900218ba7c4022e44f2993df59d56d5b15887572f4d4aa3774072784d450', '0xb512763afab43776c56a4c29c06302db4f7af60042ba1ec2c205ca5b75445a2e', 'external', 'Chainlink Labs', '2026-12-15', NULL, 'critical', 'org-gwm-da', 'draft', NULL, NULL, '2026-07-01', 'Bridges introduce supply, finality, and counterparty risk. Requires a separate control assessment.'),
('tpl-por-100', 'PROOF_OF_RESERVE_REGISTRY', 'Proof-of-Reserve Registry', '1.0.0', 'attestation', 'AttestationRegistry', 'Stores auditor attestations and reserve coverage snapshots on-chain.', 'https://git.bank.internal/sc/proof-of-reserve', 'contracts/ProofOfReserve.sol', '0xef2028a33ca1f007f867bbc3fe900e9376267148a9ea915b39e1fae7f68f6b39', '0.8.24', 'shanghai', 'Internal', '0x4cba7853cd13a00f640249b9049b37e263b93d578c61070d4db745a7cd5d44a8', '0x4cba7853cd13a00f640249b9049b37e263b93d578c61070d4db745a7cd5d44a8', '0xe2e71cacec13365522f10446ef74b952928b8addda8c2da91698827fb79ba27b', 'external', 'Nethermind', '2027-05-31', NULL, 'high', 'org-gwm-com', 'approved', '2025-10-01', NULL, '2025-09-01', 'Anchors hashes, not bar lists or client data.'),
('tpl-collateral-100', 'GOLD_COLLATERAL_VAULT', 'Gold Collateral Vault', '1.0.0', 'value', 'CollateralVault', 'Locks gold tokens as collateral and releases them on repayment or liquidation.', 'https://git.bank.internal/sc/collateral-vault', 'contracts/GoldCollateralVault.sol', '0x7044b9a0844d60b5ce78ad48170a0493f839cd7253e56d2c111dec19d97ecf44', '0.8.24', 'shanghai', 'Internal', '0x5dde60e8fdf3d00e1668b56ccd09a2988ec30812379de4c7dabc837dfcb8186c', '0x5dde60e8fdf3d00e1668b56ccd09a2988ec30812379de4c7dabc837dfcb8186c', '0xc18f7629418d4e7162e0364efdc00c0c8372ea11099a6f21784c287df9decae5', 'external', 'ChainSecurity', '2027-08-31', NULL, 'critical', 'org-gwm-da', 'approved', '2026-06-30', NULL, '2026-05-15', 'First production deployment is pending critical-risk approval.'),
('tpl-chf-deposit-100', 'CHF_DEPOSIT_TOKEN', 'CHF Deposit Token', '1.0.0', 'token', 'DepositToken', 'Permissioned CHF cash leg for DvP and internal settlement.', 'https://git.bank.internal/sc/chf-deposit', 'contracts/CHFDepositToken.sol', '0xd1aabe14eac5d810fc0396f6ef83716f107739d330f81c81176bbd0ed66692dc', '0.8.24', 'shanghai', 'Internal', '0x6222951902acb36083736c4fd16cf44e6929d4d8ed3a95f94f098e87747f5dd6', '0x6222951902acb36083736c4fd16cf44e6929d4d8ed3a95f94f098e87747f5dd6', '0xe6f9c289c8fbaf260cefda27a9958f891024b39387eff6754bf5f7501615ddfe', 'external', 'Halborn', '2027-01-31', NULL, 'high', 'org-gwm-da', 'approved', '2026-03-01', NULL, '2026-02-01', 'Cash leg is not counted toward the gold reserve.'),
('tpl-chainlink-feed-100', 'CHAINLINK_AGGREGATOR', 'Chainlink XAU/USD Aggregator', '1.0.0', 'oracle', 'ExternalOracle', 'Third-party price feed consumed by the gold oracle adapter.', 'https://docs.chain.link/data-feeds', 'external', '0xe0763d091dc4b18956fc159fb755a4a862c7cd977a4651053d4777fc5aae1d51', NULL, NULL, 'Proprietary', '0x7bd8bb2e4e7b66a40cebbe6b5dc06b49e95ae0df75c6598082a91ad475500b95', '0x7bd8bb2e4e7b66a40cebbe6b5dc06b49e95ae0df75c6598082a91ad475500b95', '0xbfe6e94b1531ca865b8cdf967b4411fe8efd36365df5a41b94bcd7d5aa513dd4', 'external', 'Chainlink Labs', '2027-01-31', NULL, 'high', 'org-gwm-com', 'approved', '2025-01-01', NULL, '2025-01-01', 'External dependency; source not verified by the bank.'),
('tpl-erc4337-100', 'ERC4337_SMART_ACCOUNT', 'ERC-4337 Smart Account', '1.0.0', 'account', 'SmartAccount', 'Programmable account with session keys and paymaster support. Future capability.', 'https://github.com/erc4337/account-abstraction', 'contracts/accounts/SimpleAccount.sol', '0xb5d58c39b4accec5b419f70c3dd801ead80c3b63c17935638c9b57cc9bbfea00', '0.8.24', 'shanghai', 'MIT', '0xed666a60e83af8d2390453762dd419497a484b483ef78dc4784a2feb12703343', '0xed666a60e83af8d2390453762dd419497a484b483ef78dc4784a2feb12703343', NULL, 'external', 'OpenZeppelin', '2027-06-30', NULL, 'high', 'org-cio-plt', 'draft', NULL, NULL, '2026-09-01', 'Future operating-model capability; not yet deployed.'),
('tpl-zk-verifier-100', 'GROTH16_VERIFIER', 'Groth16 Verifier', '1.0.0', 'privacy', 'Verifier', 'Verifies privacy-preserving eligibility proofs. Future capability.', 'https://github.com/zkverify', 'contracts/Groth16Verifier.sol', '0x0381cdceb318da0feac5f6de2f22002d35ee7bb8fe48f08b14385a099e0ac353', '0.8.24', 'shanghai', 'Apache-2.0', '0x6fc84e142e4d6b77d74195c36618a2041ea8e558122d3f693f71319f3fb38100', '0x6fc84e142e4d6b77d74195c36618a2041ea8e558122d3f693f71319f3fb38100', NULL, 'external', 'Trail of Bits', '2027-07-31', NULL, 'critical', 'org-cio-plt', 'draft', NULL, NULL, '2026-09-15', 'Future privacy capability; trust setup and verifier-key governance are unresolved.');

INSERT INTO template_standard (template_id, standard_code, conformance, notes) VALUES
('tpl-cmtat-230', 'ERC-20', 'full', NULL),
('tpl-cmtat-230', 'ERC-3643', 'partial', 'Token interface only; no on-chain identity dependency.'),
('tpl-cmtat-230', 'ERC-1404', 'partial', 'Restriction interface.'),
('tpl-cmtat-230', 'CMTAT', 'full', NULL),
('tpl-cmtat-300', 'ERC-20', 'full', NULL),
('tpl-cmtat-300', 'ERC-3643', 'partial', 'Token interface only; identity is handled by service layer.'),
('tpl-cmtat-300', 'ERC-1404', 'partial', 'Restriction interface.'),
('tpl-cmtat-300', 'ERC-1643', 'partial', 'Documents extension.'),
('tpl-cmtat-300', 'CMTAT', 'full', NULL),
('tpl-cmtat-320', 'ERC-20', 'full', NULL),
('tpl-cmtat-320', 'ERC-3643', 'partial', NULL),
('tpl-cmtat-320', 'ERC-1404', 'partial', NULL),
('tpl-cmtat-320', 'ERC-1643', 'partial', NULL),
('tpl-cmtat-320', 'ERC-7802', 'partial', 'Cross-chain extension.'),
('tpl-cmtat-320', 'CMTAT', 'full', NULL),
('tpl-cmtat-uups-300', 'ERC-20', 'full', NULL),
('tpl-cmtat-uups-300', 'ERC-3643', 'partial', NULL),
('tpl-cmtat-uups-300', 'ERC-1404', 'partial', NULL),
('tpl-cmtat-uups-300', 'ERC-1643', 'partial', NULL),
('tpl-cmtat-uups-300', 'ERC-1967', 'full', NULL),
('tpl-cmtat-uups-300', 'ERC-1822', 'full', NULL),
('tpl-cmtat-uups-300', 'CMTAT', 'full', NULL),
('tpl-ruleengine-100', 'CMTAT-RULE-ENGINE', 'full', NULL),
('tpl-ruleengine-100', 'ERC-1404', 'partial', 'Returns restriction codes.'),
('tpl-rule-maxholders-110', 'CMTAT-RULE-ENGINE', 'full', NULL),
('tpl-rule-country-100', 'CMTAT-RULE-ENGINE', 'full', NULL),
('tpl-identity-100', 'ERC-3643', 'full', NULL),
('tpl-identity-100', 'ONCHAINID', 'full', NULL),
('tpl-identity-100', 'ERC-165', 'full', NULL),
('tpl-trusted-100', 'ERC-3643', 'full', NULL),
('tpl-trusted-100', 'ONCHAINID', 'partial', NULL),
('tpl-claim-100', 'ERC-3643', 'full', NULL),
('tpl-claim-100', 'ONCHAINID', 'partial', NULL),
('tpl-dvp-100', 'CMTAT-DVP', 'full', NULL),
('tpl-dvp-100', 'ERC-20', 'partial', NULL),
('tpl-escrow-120', 'CUSTOM-ESCROW', 'full', NULL),
('tpl-erc4626-100', 'ERC-4626', 'full', NULL),
('tpl-erc4626-100', 'ERC-20', 'full', NULL),
('tpl-multicall-300', 'MULTICALL3', 'full', NULL),
('tpl-factory-100', 'ERC-1014', 'full', NULL),
('tpl-factory-100', 'ERC-1167', 'partial', 'Clone mode.'),
('tpl-factory-100', 'ERC-1967', 'partial', 'Proxy mode.'),
('tpl-factory-100', 'CMTAT', 'partial', NULL),
('tpl-proxy-100', 'ERC-1967', 'full', NULL),
('tpl-proxy-100', 'ERC-1822', 'full', NULL),
('tpl-oracle-100', 'CHAINLINK-AGGREGATOR-V3', 'partial', 'Consumer of the interface.'),
('tpl-timelock-100', 'OPENZEPPELIN-TIMELOCK', 'full', NULL),
('tpl-safe-140', 'GNOSIS-SAFE', 'full', NULL),
('tpl-safe-140', 'ERC-1271', 'full', NULL),
('tpl-safe-140', 'ERC-165', 'full', NULL),
('tpl-ccip-100', 'CHAINLINK-CCIP', 'full', NULL),
('tpl-ccip-100', 'ERC-20', 'partial', NULL),
('tpl-ccip-100', 'ERC-7802', 'partial', NULL),
('tpl-por-100', 'ATTESTATION-REGISTRY', 'full', NULL),
('tpl-chf-deposit-100', 'ERC-20', 'full', NULL),
('tpl-chf-deposit-100', 'ERC-1404', 'partial', NULL),
('tpl-chainlink-feed-100', 'CHAINLINK-AGGREGATOR-V3', 'full', NULL),
('tpl-erc4337-100', 'ERC-4337', 'full', NULL),
('tpl-erc4337-100', 'ERC-1271', 'full', NULL),
('tpl-zk-verifier-100', 'GROTH16-VERIFIER', 'full', NULL);

INSERT INTO template_dependency (id, template_id, depends_on_template_id, relation, version_constraint) VALUES
('td-01', 'tpl-cmtat-300', 'tpl-ruleengine-100', 'compatible_with', '>=1.0.0'),
('td-02', 'tpl-cmtat-uups-300', 'tpl-proxy-100', 'uses', '>=1.0.0'),
('td-03', 'tpl-factory-100', 'tpl-proxy-100', 'uses', '>=1.0.0'),
('td-04', 'tpl-dvp-100', 'tpl-cmtat-300', 'uses', '>=3.0.0'),
('td-05', 'tpl-collateral-100', 'tpl-cmtat-300', 'uses', '>=3.0.0'),
('td-06', 'tpl-ccip-100', 'tpl-cmtat-300', 'uses', '>=3.2.0'),
('td-07', 'tpl-cmtat-320', 'tpl-cmtat-300', 'compatible_with', '>=3.0.0');

INSERT INTO template_parameter (id, template_id, name, data_type, required, default_value, description, sensitive) VALUES
('tp-01', 'tpl-cmtat-300', 'tokenName', 'string', 1, NULL, 'Token name', 0),
('tp-02', 'tpl-cmtat-300', 'tokenSymbol', 'string', 1, NULL, 'Token symbol', 0),
('tp-03', 'tpl-cmtat-300', 'decimals', 'uint8', 1, '0', 'Base-unit decimals', 0),
('tp-04', 'tpl-cmtat-300', 'maxSupply', 'uint256', 1, NULL, 'Supply cap in base units', 0),
('tp-05', 'tpl-cmtat-300', 'ruleEngine', 'address', 0, NULL, 'External RuleEngine address', 0),
('tp-06', 'tpl-cmtat-300', 'admin', 'address', 1, NULL, 'Admin / owner address', 0),
('tp-07', 'tpl-cmtat-300', 'termsURI', 'string', 1, NULL, 'Legal terms document URI', 0),
('tp-08', 'tpl-cmtat-uups-300', 'tokenName', 'string', 1, NULL, 'Token name', 0),
('tp-09', 'tpl-cmtat-uups-300', 'tokenSymbol', 'string', 1, NULL, 'Token symbol', 0),
('tp-10', 'tpl-cmtat-uups-300', 'decimals', 'uint8', 1, '0', 'Base-unit decimals', 0),
('tp-11', 'tpl-cmtat-uups-300', 'maxSupply', 'uint256', 1, NULL, 'Supply cap in base units', 0),
('tp-12', 'tpl-cmtat-uups-300', 'ruleEngine', 'address', 0, NULL, 'External RuleEngine address', 0),
('tp-13', 'tpl-cmtat-uups-300', 'admin', 'address', 1, NULL, 'Timelock / Safe address', 0),
('tp-14', 'tpl-cmtat-uups-300', 'termsURI', 'string', 1, NULL, 'Legal terms document URI', 0),
('tp-15', 'tpl-ruleengine-100', 'admin', 'address', 1, NULL, 'Rule engine admin', 0),
('tp-16', 'tpl-ruleengine-100', 'rules', 'address[]', 1, NULL, 'Initial rule set', 0),
('tp-17', 'tpl-rule-maxholders-110', 'maxHolders', 'uint256', 1, '500', 'Maximum number of holders', 0),
('tp-18', 'tpl-rule-maxholders-110', 'admin', 'address', 1, NULL, 'Rule admin', 0),
('tp-19', 'tpl-rule-country-100', 'allowedCountries', 'uint16[]', 1, NULL, 'ISO-3166 numeric country codes', 0),
('tp-20', 'tpl-rule-country-100', 'admin', 'address', 1, NULL, 'Rule admin', 0),
('tp-21', 'tpl-oracle-100', 'feed', 'address', 1, NULL, 'Chainlink aggregator address', 0),
('tp-22', 'tpl-oracle-100', 'heartbeatSeconds', 'uint256', 1, '3600', 'Maximum age of a price', 0),
('tp-23', 'tpl-oracle-100', 'deviationBps', 'uint16', 1, '100', 'Maximum price deviation', 0),
('tp-24', 'tpl-dvp-100', 'assetToken', 'address', 1, NULL, 'Delivery leg token', 0),
('tp-25', 'tpl-dvp-100', 'paymentToken', 'address', 1, NULL, 'Payment leg token', 0),
('tp-26', 'tpl-dvp-100', 'settlementWindow', 'uint256', 1, '300', 'Seconds allowed for settlement', 0),
('tp-27', 'tpl-proxy-100', 'implementation', 'address', 1, NULL, 'Initial implementation', 0),
('tp-28', 'tpl-proxy-100', 'admin', 'address', 1, NULL, 'Proxy admin', 0),
('tp-29', 'tpl-factory-100', 'implementation', 'address', 1, NULL, 'Implementation or beacon', 0),
('tp-30', 'tpl-factory-100', 'beacon', 'address', 0, NULL, 'Optional beacon address', 0),
('tp-31', 'tpl-factory-100', 'salt', 'bytes32', 1, NULL, 'CREATE2 salt', 0),
('tp-32', 'tpl-por-100', 'reserveAsset', 'string', 1, 'XAU', 'Reserve asset code', 0),
('tp-33', 'tpl-por-100', 'auditor', 'string', 1, NULL, 'Attestation provider', 0),
('tp-34', 'tpl-por-100', 'attestationIntervalDays', 'uint16', 1, '30', 'Maximum age of an attestation', 0),
('tp-35', 'tpl-collateral-100', 'goldToken', 'address', 1, NULL, 'Gold token address', 0),
('tp-36', 'tpl-collateral-100', 'paymentToken', 'address', 1, NULL, 'Cash token address', 0),
('tp-37', 'tpl-collateral-100', 'ltvBps', 'uint16', 1, '6000', 'Maximum loan-to-value', 0),
('tp-38', 'tpl-collateral-100', 'liquidationThresholdBps', 'uint16', 1, '7500', 'Liquidation threshold', 0),
('tp-39', 'tpl-chf-deposit-100', 'tokenName', 'string', 1, NULL, 'Token name', 0),
('tp-40', 'tpl-chf-deposit-100', 'tokenSymbol', 'string', 1, NULL, 'Token symbol', 0),
('tp-41', 'tpl-chf-deposit-100', 'decimals', 'uint8', 1, '2', 'Base-unit decimals', 0),
('tp-42', 'tpl-chf-deposit-100', 'admin', 'address', 1, NULL, 'Admin address', 0),
('tp-43', 'tpl-safe-140', 'threshold', 'uint8', 1, '3', 'Confirmation threshold', 0),
('tp-44', 'tpl-safe-140', 'owners', 'address[]', 1, NULL, 'Owner addresses', 0),
('tp-45', 'tpl-timelock-100', 'minDelay', 'uint256', 1, '172800', 'Minimum delay in seconds', 0),
('tp-46', 'tpl-timelock-100', 'proposers', 'address[]', 1, NULL, 'Proposer addresses', 0),
('tp-47', 'tpl-timelock-100', 'executors', 'address[]', 1, NULL, 'Executor addresses', 0),
('tp-48', 'tpl-ccip-100', 'router', 'address', 1, NULL, 'CCIP router', 0),
('tp-49', 'tpl-ccip-100', 'chainSelector', 'uint64', 1, NULL, 'Destination chain selector', 0),
('tp-50', 'tpl-ccip-100', 'remoteToken', 'address', 1, NULL, 'Remote token address', 0),
('tp-51', 'tpl-chainlink-feed-100', 'aggregator', 'address', 1, NULL, 'Aggregator proxy', 0),
('tp-52', 'tpl-chainlink-feed-100', 'heartbeatSeconds', 'uint256', 1, '3600', 'Heartbeat', 0),
('tp-53', 'tpl-chainlink-feed-100', 'decimals', 'uint8', 1, '8', 'Feed decimals', 0),
('tp-54', 'tpl-escrow-120', 'arbiter', 'address', 1, NULL, 'Arbiter address', 0),
('tp-55', 'tpl-escrow-120', 'assetToken', 'address', 1, NULL, 'Asset held in escrow', 0),
('tp-56', 'tpl-escrow-120', 'releaseCondition', 'string', 1, NULL, 'Human-readable release condition hash', 0);

INSERT INTO software_ci (id, ci_name, ci_type, owner_org_unit_id, support_group, lifecycle_status, criticality, cmdb_url) VALUES
('ci-app-gold', 'Digital Gold Token Platform', 'application', 'org-gwm-da', 'Digital Assets Engineering', 'active', 'critical', 'https://cmdb.bank.internal/ci/APP-1042'),
('ci-app-factory', 'Tokenization Factory', 'platform', 'org-cio-plt', 'Platform Engineering', 'active', 'high', 'https://cmdb.bank.internal/ci/APP-2088'),
('ci-app-compliance', 'On-chain Compliance Services', 'application', 'org-cco', 'Compliance Technology', 'active', 'critical', 'https://cmdb.bank.internal/ci/APP-3091'),
('ci-app-settlement', 'DvP Settlement Service', 'application', 'org-gwm-da', 'Digital Assets Engineering', 'active', 'critical', 'https://cmdb.bank.internal/ci/APP-4107'),
('ci-app-registry', 'Smart Contract Registry', 'platform', 'org-cio-plt', 'Platform Engineering', 'active', 'high', 'https://cmdb.bank.internal/ci/APP-5150');

INSERT INTO template_ci (template_id, ci_id, relation) VALUES
('tpl-cmtat-300', 'ci-app-gold', 'part_of'),
('tpl-cmtat-uups-300', 'ci-app-gold', 'part_of'),
('tpl-cmtat-230', 'ci-app-gold', 'part_of'),
('tpl-cmtat-320', 'ci-app-gold', 'part_of'),
('tpl-chf-deposit-100', 'ci-app-gold', 'part_of'),
('tpl-collateral-100', 'ci-app-gold', 'part_of'),
('tpl-oracle-100', 'ci-app-gold', 'part_of'),
('tpl-por-100', 'ci-app-gold', 'part_of'),
('tpl-factory-100', 'ci-app-factory', 'part_of'),
('tpl-proxy-100', 'ci-app-factory', 'part_of'),
('tpl-multicall-300', 'ci-app-factory', 'part_of'),
('tpl-safe-140', 'ci-app-factory', 'part_of'),
('tpl-timelock-100', 'ci-app-factory', 'part_of'),
('tpl-ruleengine-100', 'ci-app-compliance', 'part_of'),
('tpl-rule-maxholders-110', 'ci-app-compliance', 'part_of'),
('tpl-rule-country-100', 'ci-app-compliance', 'part_of'),
('tpl-identity-100', 'ci-app-compliance', 'part_of'),
('tpl-trusted-100', 'ci-app-compliance', 'part_of'),
('tpl-claim-100', 'ci-app-compliance', 'part_of'),
('tpl-dvp-100', 'ci-app-settlement', 'part_of'),
('tpl-escrow-120', 'ci-app-settlement', 'part_of');

INSERT INTO approval_policy (id, object_type, risk_tier, gate, required_role, min_approvals, blocking, sequence, description) VALUES
('pol-dep-high-01', 'deployment', 'high', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms commercial rationale and accountability.'),
('pol-dep-high-02', 'deployment', 'high', 'PRODUCT', 'Product Owner', 1, 1, 2, 'Product owner confirms the deployment matches the approved product design.'),
('pol-dep-high-03', 'deployment', 'high', 'COMPLIANCE', 'Compliance', 1, 1, 3, 'Compliance confirms AML, sanctions and transfer-restriction requirements.'),
('pol-dep-high-04', 'deployment', 'high', 'LEGAL', 'Legal', 1, 1, 4, 'Legal confirms the legal wrapper, terms and jurisdiction.'),
('pol-dep-high-05', 'deployment', 'high', 'RISK', 'Operational Risk', 1, 1, 5, 'Operational risk confirms the control assessment and residual risk.'),
('pol-dep-high-06', 'deployment', 'high', 'SECURITY', 'Security', 1, 1, 6, 'Security confirms bytecode match, audit validity and key-management controls.'),
('pol-dep-high-07', 'deployment', 'high', 'OPS', 'Platform Operations', 1, 1, 7, 'Operations confirms monitoring, runbooks and rollback capability.'),
('pol-dep-high-08', 'deployment', 'high', 'CAB', 'Change Advisory Board', 1, 1, 8, 'CAB confirms the production change window and incident readiness.'),
('pol-dep-critical-01', 'deployment', 'critical', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms commercial rationale and accountability.'),
('pol-dep-critical-02', 'deployment', 'critical', 'PRODUCT', 'Product Owner', 1, 1, 2, 'Product owner confirms the approved product design.'),
('pol-dep-critical-03', 'deployment', 'critical', 'COMPLIANCE', 'Compliance', 1, 1, 3, 'Compliance confirms AML, sanctions and transfer restrictions.'),
('pol-dep-critical-04', 'deployment', 'critical', 'LEGAL', 'Legal', 1, 1, 4, 'Legal confirms the legal wrapper and jurisdictional opinion.'),
('pol-dep-critical-05', 'deployment', 'critical', 'RISK', 'Operational Risk', 1, 1, 5, 'Operational risk confirms the control assessment.'),
('pol-dep-critical-06', 'deployment', 'critical', 'SECURITY', 'Security', 1, 1, 6, 'Security confirms the technical assurance package.'),
('pol-dep-critical-07', 'deployment', 'critical', 'DATA_PROTECTION', 'Data Protection', 1, 1, 7, 'DPO confirms no personal data is written on-chain and privacy groups are correct.'),
('pol-dep-critical-08', 'deployment', 'critical', 'MODEL_RISK', 'Model Risk', 1, 1, 8, 'Model risk validates rule logic that materially affects client outcomes.'),
('pol-dep-critical-09', 'deployment', 'critical', 'OPS', 'Platform Operations', 1, 1, 9, 'Operations confirms monitoring, runbooks and rollback capability.'),
('pol-dep-critical-10', 'deployment', 'critical', 'CAB', 'Change Advisory Board', 1, 1, 10, 'CAB confirms the production change window and incident readiness.'),
('pol-dep-medium-01', 'deployment', 'medium', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms rationale.'),
('pol-dep-medium-02', 'deployment', 'medium', 'COMPLIANCE', 'Compliance', 1, 1, 2, 'Compliance confirms applicable requirements.'),
('pol-dep-medium-03', 'deployment', 'medium', 'RISK', 'Operational Risk', 1, 1, 3, 'Risk confirms the control assessment.'),
('pol-dep-medium-04', 'deployment', 'medium', 'SECURITY', 'Security', 1, 1, 4, 'Security confirms technical assurance.'),
('pol-dep-medium-05', 'deployment', 'medium', 'OPS', 'Platform Operations', 1, 1, 5, 'Operations confirms monitoring and runbooks.'),
('pol-dep-low-01', 'deployment', 'low', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms rationale.'),
('pol-dep-low-02', 'deployment', 'low', 'OPS', 'Platform Operations', 1, 1, 2, 'Operations confirms the environment and monitoring.'),
('pol-tpl-high-01', 'template', 'high', 'ARCHITECTURE', 'Platform Architect', 1, 1, 1, 'Architecture review of the template and dependency chain.'),
('pol-tpl-high-02', 'template', 'high', 'SECURITY', 'Security', 1, 1, 2, 'Security review of source, compiler and known vulnerabilities.'),
('pol-tpl-high-03', 'template', 'high', 'AUDIT_EVIDENCE', 'Operational Risk', 1, 1, 3, 'Risk accepts the audit scope, findings and residual risk.'),
('pol-tpl-high-04', 'template', 'high', 'LEGAL', 'Legal', 1, 1, 4, 'Legal confirms licence and contractual usability.'),
('pol-tpl-high-05', 'template', 'high', 'SOURCING', 'Platform Operations', 1, 1, 5, 'Operations confirms support, ownership and lifecycle.'),
('pol-tpl-critical-01', 'template', 'critical', 'ARCHITECTURE', 'Platform Architect', 1, 1, 1, 'Architecture review of the template and dependency chain.'),
('pol-tpl-critical-02', 'template', 'critical', 'SECURITY', 'Security', 1, 1, 2, 'Security review of source, compiler and known vulnerabilities.'),
('pol-tpl-critical-03', 'template', 'critical', 'AUDIT_EVIDENCE', 'Operational Risk', 1, 1, 3, 'Risk accepts the audit scope, findings and residual risk.'),
('pol-tpl-critical-04', 'template', 'critical', 'LEGAL', 'Legal', 1, 1, 4, 'Legal confirms licence and contractual usability.'),
('pol-tpl-critical-05', 'template', 'critical', 'DATA_PROTECTION', 'Data Protection', 1, 1, 5, 'DPO confirms privacy-by-design and off-chain data boundaries.'),
('pol-tpl-critical-06', 'template', 'critical', 'SOURCING', 'Platform Operations', 1, 1, 6, 'Operations confirms support, ownership and lifecycle.'),
('pol-tpl-medium-01', 'template', 'medium', 'ARCHITECTURE', 'Platform Architect', 1, 1, 1, 'Architecture review.'),
('pol-tpl-medium-02', 'template', 'medium', 'SECURITY', 'Security', 1, 1, 2, 'Security review.'),
('pol-tpl-medium-03', 'template', 'medium', 'SOURCING', 'Platform Operations', 1, 1, 3, 'Support and lifecycle review.'),
('pol-chg-high-01', 'change', 'high', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms the change rationale.'),
('pol-chg-high-02', 'change', 'high', 'COMPLIANCE', 'Compliance', 1, 1, 2, 'Compliance confirms the change does not alter client entitlements incorrectly.'),
('pol-chg-high-03', 'change', 'high', 'RISK', 'Operational Risk', 1, 1, 3, 'Risk confirms the change assessment.'),
('pol-chg-high-04', 'change', 'high', 'SECURITY', 'Security', 1, 1, 4, 'Security confirms the technical change is safe.'),
('pol-chg-high-05', 'change', 'high', 'OPS', 'Platform Operations', 1, 1, 5, 'Operations confirms execution and rollback.'),
('pol-chg-high-06', 'change', 'high', 'CAB', 'Change Advisory Board', 1, 1, 6, 'CAB approves the production change.'),
('pol-chg-critical-01', 'change', 'critical', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms the change rationale.'),
('pol-chg-critical-02', 'change', 'critical', 'COMPLIANCE', 'Compliance', 1, 1, 2, 'Compliance confirms regulatory impact.'),
('pol-chg-critical-03', 'change', 'critical', 'RISK', 'Operational Risk', 1, 1, 3, 'Risk confirms the change assessment.'),
('pol-chg-critical-04', 'change', 'critical', 'SECURITY', 'Security', 1, 1, 4, 'Security confirms the technical change is safe.'),
('pol-chg-critical-05', 'change', 'critical', 'DATA_PROTECTION', 'Data Protection', 1, 1, 5, 'DPO confirms privacy impact.'),
('pol-chg-critical-06', 'change', 'critical', 'MODEL_RISK', 'Model Risk', 1, 1, 6, 'Model risk confirms rule-logic changes.'),
('pol-chg-critical-07', 'change', 'critical', 'OPS', 'Platform Operations', 1, 1, 7, 'Operations confirms execution and rollback.'),
('pol-chg-critical-08', 'change', 'critical', 'CAB', 'Change Advisory Board', 1, 1, 8, 'CAB approves the production change.'),
('pol-chg-medium-01', 'change', 'medium', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms the change rationale.'),
('pol-chg-medium-02', 'change', 'medium', 'RISK', 'Operational Risk', 1, 1, 2, 'Risk confirms the change assessment.'),
('pol-chg-medium-03', 'change', 'medium', 'SECURITY', 'Security', 1, 1, 3, 'Security confirms the technical change is safe.'),
('pol-chg-medium-04', 'change', 'medium', 'OPS', 'Platform Operations', 1, 1, 4, 'Operations confirms execution and rollback.'),
('pol-chg-low-01', 'change', 'low', 'BUSINESS', 'Business Owner', 1, 1, 1, 'Business owner confirms the change rationale.'),
('pol-chg-low-02', 'change', 'low', 'OPS', 'Platform Operations', 1, 1, 2, 'Operations executes the change.');

INSERT INTO deployment_request (id, template_id, chain_id, environment, requested_by, business_owner_id, org_unit_id, product_name, legal_entity, jurisdiction, risk_tier, config_hash, init_params_json, salt, manifest_hash, status, change_ticket, target_window, created_at, approved_at, notes) VALUES
('DR-2026-0031', 'tpl-cmtat-uups-300', 'ch-eth-mainnet', 'PROD', 'p-priya', 'p-elena', 'org-gwm-com', 'UBGX Gold Token (Public)', 'Financial Institution AG', 'CH', 'critical', '0x73fca966f27b3643c8c672eb52c3fb3b6b0a3d6b64800940f538f9e708462d4b', '{"name":"Gold Token","symbol":"UBGX","decimals":4,"maxSupply":"1250000000","ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25","admin":"0xf26274801325d20a15a830ce48cdae4f79fd907f","termsURI":"ipfs://bafybeigoldterms"}', '0x972c482a0d86076608c98029a53948e918837013d119f6bec7fd6acd8b275b28', '0xc29d06a92be6b69fae2b8a72e4e4d2199bd92b5803ebc37aa7d26a01e69f14ab', 'deployed', 'CHG-8601', '2026-02-11 07:00-09:00 UTC', '2026-01-15T09:20:00Z', '2026-02-05T16:10:00Z', 'Critical-risk public issuance. Timelock admin and 3-of-5 Safe control.'),
('DR-2026-0042', 'tpl-cmtat-300', 'ch-besu-prod', 'PROD', 'p-priya', 'p-elena', 'org-gwm-com', 'UBGX Gold Token (Ledger)', 'Financial Institution AG', 'CH', 'high', '0x908cd4b7ada2d6b4408999a764e9b49736654e487543f385e8b6e56d19bcd353', '{"name":"UBGX Gold Token (Ledger)","symbol":"UBGX","decimals":4,"maxSupply":"500000000","ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25","admin":"0xc3b5e332056d18c4febe491b0a27049887df48dd","termsURI":"ipfs://bafybeigoldterms"}', '0x4f8ad0955e2b21909aa1a78e404c0371f0f075b6923d510cbb19c01c715b71c2', '0xdabf4200b454ee8846ce107ed0411581815c4ce97951776f0fd5c109f7160dab', 'deployed', 'CHG-8841', '2026-03-18 10:00-12:00 UTC', '2026-02-20T13:40:00Z', '2026-03-15T11:05:00Z', 'Permissioned ledger deployment for private-banking clients.'),
('DR-2026-0051', 'tpl-cmtat-300', 'ch-besu-prod', 'PROD', 'p-priya', 'p-luca', 'org-gwm-lux', 'UBGX Gold Token (Luxembourg)', 'European Entity (Luxembourg) S.A.', 'LU', 'high', '0x71b9717073278b37348942ae0cc94634b66b24ffe6a2fc49ba7ee034d9ac5ea0', '{"name":"UBGX Gold Token (Lux)","symbol":"UBGXL","decimals":4,"maxSupply":"250000000","ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25","admin":"0xc3b5e332056d18c4febe491b0a27049887df48dd","termsURI":"ipfs://bafybeigoldtermslux"}', '0x752b770c23b79c502edd10aace3740d0c5cd4a7e80e9bc044f150a2604cc13a2', '0x602713420047f8cd2e67e24504df171db41790f2a018c0cae504514c88c140c6', 'in_review', 'CHG-9117', '2026-11-10 09:00-11:00 UTC', '2026-10-19T08:15:00Z', NULL, 'Luxembourg legal entity and separate reserve pool.'),
('DR-2026-0053', 'tpl-cmtat-300', 'ch-besu-uat', 'UAT', 'p-priya', 'p-marco', 'org-gwm-da', 'UBGX Gold Token (UAT)', 'Financial Institution AG', 'CH', 'low', '0x8aa3afa205b4dd32e6a2da8e0cacc6f5eb09d25aa8a59915d1ea19055b32eeba', '{"name":"UBGX Gold Token (UAT)","symbol":"UBGX","decimals":4,"maxSupply":"10000000","ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25","admin":"0xc3b5e332056d18c4febe491b0a27049887df48dd","termsURI":"ipfs://bafybeigoldtermsuat"}', '0x3a91e13faa6bfad3a8c4453ba4d884b61c633d7723855f928b5ddddfbef19e12', '0xe5e0ebf922d0a432029c79c9e4522dfe9a20870c6e7a04e4e5d90839a975900c', 'deployed', 'CHG-9002', '2026-09-30 13:00-14:00 UTC', '2026-09-25T10:30:00Z', '2026-09-28T15:00:00Z', 'Test environment. No real gold backing.'),
('DR-2026-0055', 'tpl-cmtat-300', 'ch-besu-uat', 'UAT', 'p-priya', 'p-luca', 'org-gwm-lux', 'UBGX Gold Token (Lux UAT)', 'European Entity (Luxembourg) S.A.', 'LU', 'low', '0x18e51660a29840560f13c4fea8a52af8e5f418a7927c0bbe5d3fd8122ddbe74c', '{"name":"UBGX Gold Token (Lux UAT)","symbol":"UBGXL","decimals":4,"maxSupply":"5000000","ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25","admin":"0xc3b5e332056d18c4febe491b0a27049887df48dd","termsURI":"ipfs://bafybeigoldtermsluxuat"}', '0x752b770c23b79c502edd10aace3740d0c5cd4a7e80e9bc044f150a2604cc13a2', '0x918e87a7fdc6057c4de21011324ff71b19b66b84d9a34a7a9247c39866e4296d', 'deployed', 'CHG-9090', '2026-10-22 08:00-09:00 UTC', '2026-10-20T09:10:00Z', '2026-10-21T14:00:00Z', 'Canary for Luxembourg production deployment.'),
('DR-2026-0060', 'tpl-cmtat-320', 'ch-eth-mainnet', 'PROD', 'p-priya', 'p-elena', 'org-gwm-com', 'UBGX Pilot 3.2', 'Financial Institution AG', 'CH', 'high', '0xe10ce7994af984a675134dc0da885d85ef1afcc5662cdec70c99ee2edd6a5fc3', '{"name":"UBGX Pilot 3.2","symbol":"UBGXP","decimals":4,"maxSupply":"10000000","ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25","admin":"0xf26274801325d20a15a830ce48cdae4f79fd907f","termsURI":"ipfs://bafybeigoldterms32"}', '0x972c482a0d86076608c98029a53948e918837013d119f6bec7fd6acd8b275b28', '0x0bb663ca6284450d858391c070d958e53acfb5ba1aca3d3b0e73143d2163c04b', 'in_review', 'CHG-9131', '2026-11-24 09:00-10:00 UTC', '2026-10-02T11:25:00Z', NULL, 'Pilot request intentionally blocked until CMTAT 3.2.0 has an independent audit.'),
('DR-2026-0063', 'tpl-collateral-100', 'ch-besu-prod', 'PROD', 'p-priya', 'p-elena', 'org-gwm-com', 'Gold Collateral Vault', 'Financial Institution AG', 'CH', 'critical', '0x373cd0eda245bd91e6fc7becf746f00352dc7fb5a5dc745610cdfac3df568d96', '{"goldToken":"0x46009f357c42ca5895de915a469cbb56b760411e","paymentToken":"0xedf975de39cda7da80d85e1a2268315af7a48bb9","ltvBps":6000,"liquidationThresholdBps":7500}', '0x4ea47ac16dd35a12dabfed10953e7946f9b83bbc3f3f282350ce03244f859ea8', '0x78ad43ea8a2d763c28afe0a319397a02d2d4185352d285f4b6ed996f2173c82d', 'in_review', 'CHG-9158', '2026-12-01 08:00-11:00 UTC', '2026-10-23T16:45:00Z', NULL, 'Critical-risk collateral product; requires DPO and Model Risk sign-off.');

UPDATE deployment_request SET signing_identity_id = 'si-eth-service' WHERE id IN ('DR-2026-0031', 'DR-2026-0060');
UPDATE deployment_request SET signing_identity_id = 'si-besu-service' WHERE id IN ('DR-2026-0042', 'DR-2026-0051', 'DR-2026-0063');
UPDATE deployment_request SET signing_identity_id = 'si-besu-uat-service' WHERE id IN ('DR-2026-0053', 'DR-2026-0055');

-- Generate one evidence row per policy gate. This keeps policy and workflow in sync.
INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
SELECT
    'so-' || lower(dr.id) || '-' || lower(replace(p.gate, ' ', '-')),
    'deployment', dr.id, p.gate, p.required_role, 'pending', dr.created_at
FROM deployment_request dr
JOIN approval_policy p
  ON p.object_type = 'deployment'
 AND p.risk_tier = dr.risk_tier;

UPDATE signoff
SET decision = 'approved',
    decided_by = CASE required_role
        WHEN 'Business Owner' THEN 'p-elena'
        WHEN 'Product Owner' THEN 'p-marco'
        WHEN 'Compliance' THEN 'p-sophie'
        WHEN 'Legal' THEN 'p-daniel'
        WHEN 'Operational Risk' THEN 'p-andrea'
        WHEN 'Security' THEN 'p-lucas'
        WHEN 'Data Protection' THEN 'p-jonas'
        WHEN 'Model Risk' THEN 'p-sara'
        WHEN 'Platform Operations' THEN 'p-nina'
        WHEN 'Change Advisory Board' THEN 'p-reto'
    END,
    decided_at = '2026-02-05T16:10:00Z',
    comments = 'Approved for production deployment.',
    evidence_uri = 'evidence://' || lower(object_id) || '/' || lower(replace(gate, ' ', '-'))
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0031';

UPDATE signoff
SET decision = 'approved',
    decided_by = CASE required_role
        WHEN 'Business Owner' THEN 'p-elena'
        WHEN 'Product Owner' THEN 'p-marco'
        WHEN 'Compliance' THEN 'p-sophie'
        WHEN 'Legal' THEN 'p-daniel'
        WHEN 'Operational Risk' THEN 'p-andrea'
        WHEN 'Security' THEN 'p-lucas'
        WHEN 'Platform Operations' THEN 'p-nina'
        WHEN 'Change Advisory Board' THEN 'p-reto'
    END,
    decided_at = '2026-03-15T11:05:00Z',
    comments = 'Approved for the permissioned ledger production deployment.',
    evidence_uri = 'evidence://' || lower(object_id) || '/' || lower(replace(gate, ' ', '-'))
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0042';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-marco', decided_at = '2026-09-28T15:00:00Z',
    comments = 'UAT canary approved.', evidence_uri = 'evidence://dr-2026-0053/business'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0053' AND gate = 'BUSINESS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-nina', decided_at = '2026-09-28T15:05:00Z',
    comments = 'UAT environment and monitoring confirmed.', evidence_uri = 'evidence://dr-2026-0053/ops'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0053' AND gate = 'OPS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-luca', decided_at = '2026-10-21T14:00:00Z',
    comments = 'Luxembourg UAT canary approved.', evidence_uri = 'evidence://dr-2026-0055/business'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0055' AND gate = 'BUSINESS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-nina', decided_at = '2026-10-21T14:05:00Z',
    comments = 'UAT environment and monitoring confirmed.', evidence_uri = 'evidence://dr-2026-0055/ops'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0055' AND gate = 'OPS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-luca', decided_at = '2026-10-20T09:30:00Z',
    comments = 'Business case and Luxembourg client mandate confirmed.', evidence_uri = 'evidence://dr-2026-0051/business'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0051' AND gate = 'BUSINESS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-marco', decided_at = '2026-10-20T10:00:00Z',
    comments = 'Product design matches the approved Luxembourg offering.', evidence_uri = 'evidence://dr-2026-0051/product'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0051' AND gate = 'PRODUCT';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-amelie', decided_at = '2026-10-21T08:15:00Z',
    comments = 'AML and transfer restrictions approved for LU distribution.', evidence_uri = 'evidence://dr-2026-0051/compliance'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0051' AND gate = 'COMPLIANCE';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-elena', decided_at = '2026-10-05T09:00:00Z',
    comments = 'Pilot business case approved, subject to audit and legal gates.', evidence_uri = 'evidence://dr-2026-0060/business'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0060' AND gate = 'BUSINESS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-sophie', decided_at = '2026-10-06T11:30:00Z',
    comments = 'No additional compliance objection; template audit gate remains blocking.', evidence_uri = 'evidence://dr-2026-0060/compliance'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0060' AND gate = 'COMPLIANCE';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-elena', decided_at = '2026-10-24T09:00:00Z',
    comments = 'Collateral product business case approved.', evidence_uri = 'evidence://dr-2026-0063/business'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0063' AND gate = 'BUSINESS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-marco', decided_at = '2026-10-24T09:20:00Z',
    comments = 'LTV and liquidation parameters confirmed.', evidence_uri = 'evidence://dr-2026-0063/product'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0063' AND gate = 'PRODUCT';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-sophie', decided_at = '2026-10-24T10:00:00Z',
    comments = 'Collateral eligibility and client disclosure reviewed.', evidence_uri = 'evidence://dr-2026-0063/compliance'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0063' AND gate = 'COMPLIANCE';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-daniel', decided_at = '2026-10-24T11:00:00Z',
    comments = 'Pledge and enforcement opinion received.', evidence_uri = 'evidence://dr-2026-0063/legal'
WHERE object_type = 'deployment' AND object_id = 'DR-2026-0063' AND gate = 'LEGAL';

INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
SELECT
    'so-' || lower(t.id) || '-' || lower(replace(p.gate, ' ', '-')),
    'template', t.id, p.gate, p.required_role, 'pending', '2026-08-01'
FROM template t
JOIN approval_policy p
  ON p.object_type = 'template'
 AND p.risk_tier = t.default_risk_tier
WHERE t.id IN ('tpl-cmtat-300', 'tpl-cmtat-uups-300', 'tpl-cmtat-320');

UPDATE signoff
SET decision = 'approved',
    decided_by = CASE required_role
        WHEN 'Platform Architect' THEN 'p-priya'
        WHEN 'Security' THEN 'p-lucas'
        WHEN 'Operational Risk' THEN 'p-andrea'
        WHEN 'Legal' THEN 'p-daniel'
        WHEN 'Platform Operations' THEN 'p-nina'
        WHEN 'Data Protection' THEN 'p-jonas'
    END,
    decided_at = '2024-10-15T14:00:00Z',
    comments = 'Template approved for production use.',
    evidence_uri = 'evidence://' || lower(object_id) || '/template-' || lower(replace(gate, ' ', '-'))
WHERE object_type = 'template' AND object_id IN ('tpl-cmtat-300', 'tpl-cmtat-uups-300');

UPDATE signoff
SET decision = 'approved', decided_by = 'p-priya', decided_at = '2026-08-20T10:00:00Z',
    comments = 'Architecture review passed; independent audit is the blocking gate.',
    evidence_uri = 'evidence://tpl-cmtat-320/architecture'
WHERE object_type = 'template' AND object_id = 'tpl-cmtat-320' AND gate = 'ARCHITECTURE';

-- Every approved high/critical template must have a complete, attributable gate set.
INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
SELECT
    'so-' || lower(t.id) || '-' || lower(replace(p.gate, ' ', '-')),
    'template', t.id, p.gate, p.required_role, 'pending', '2025-06-01'
FROM template t
JOIN approval_policy p
  ON p.object_type = 'template'
 AND p.risk_tier = t.default_risk_tier
WHERE t.status = 'approved'
  AND t.default_risk_tier IN ('high', 'critical')
  AND NOT EXISTS (
      SELECT 1 FROM signoff s
      WHERE s.object_type = 'template' AND s.object_id = t.id
        AND s.gate = p.gate AND s.required_role = p.required_role
  );

UPDATE signoff
SET decision = 'approved',
    decided_by = CASE required_role
        WHEN 'Platform Architect' THEN 'p-priya'
        WHEN 'Security' THEN 'p-lucas'
        WHEN 'Operational Risk' THEN 'p-andrea'
        WHEN 'Legal' THEN 'p-daniel'
        WHEN 'Data Protection' THEN 'p-jonas'
        WHEN 'Platform Operations' THEN 'p-nina'
    END,
    decided_at = '2025-06-01T12:00:00Z',
    comments = 'Template gates approved; evidence package linked in production.',
    evidence_uri = 'evidence://' || lower(object_id) || '/template-' || lower(replace(gate, ' ', '-'))
WHERE object_type = 'template'
  AND object_id IN (
      SELECT id FROM template
      WHERE status = 'approved' AND default_risk_tier IN ('high', 'critical')
  );

INSERT INTO contract_instance (
    id, chain_id, address, template_id, instance_kind, representation,
    deployment_request_id, deployment_tx, deployer_address, deployer_type,
    block_number, deployed_at, salt, init_code_hash, runtime_code_hash,
    proxy_type, implementation_address, admin_address, beacon_address,
    status, business_owner_id, org_unit_id, legal_entity, jurisdiction,
    product_name, classification, risk_tier, criticality, privacy_group,
    is_canonical, supersedes_id, verification_status, verification_provider,
    verification_url, verified_at, last_synced_at, notes
) VALUES
('ci-ubgx-besu', 'ch-besu-prod', '0x46009f357c42ca5895de915a469cbb56b760411e', 'tpl-cmtat-300', 'logical', 'native',
 'DR-2026-0042', '0x212b490d6930d8c0947ff47cc4175a4fe2dd0913b7c11de41f10668564bd9c39', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841200, '2026-03-18T10:42:00Z', '0x4f8ad0955e2b21909aa1a78e404c0371f0f075b6923d510cbb19c01c715b71c2', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-elena', 'org-gwm-com', 'Financial Institution AG', 'CH',
 'UBGX Gold Token (Ledger)', 'Tokenized commodity / security token', 'high', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x46009f357c42ca5895de915a469cbb56b760411e', '2026-03-18T10:50:00Z', '2026-10-26T06:00:00Z', 'Private-banking book-entry token. Admin and minter roles held by the 3-of-5 Safe.'),
('ci-ubgx-besu-uat', 'ch-besu-uat', '0xd798291d6e644aaa1bf0f15a9d3aba29f22ad1ad', 'tpl-cmtat-300', 'logical', 'native',
 'DR-2026-0053', '0x457474cb7e88519c20f8cc03097cbd98d28ab25ac789fab32e138f139c91d874', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1200450, '2026-09-30T13:22:00Z', '0x3a91e13faa6bfad3a8c4453ba4d884b61c633d7723855f928b5ddddfbef19e12', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-marco', 'org-gwm-da', 'Financial Institution AG', 'CH',
 'UBGX Gold Token (UAT)', 'Tokenized commodity / test asset', 'medium', 'Tier 2', 'PG-GOLD-UAT-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-uat-explorer.bank.internal/address/0xd798291d6e644aaa1bf0f15a9d3aba29f22ad1ad', '2026-09-30T13:30:00Z', '2026-10-26T06:00:00Z', 'UAT only. No reserve backing; excluded from token supply and reserve calculations.'),
('ci-ubgx-lux-uat', 'ch-besu-uat', '0xb29eddb1d3f7b9949f46bbf16b766f6cc836046e', 'tpl-cmtat-300', 'logical', 'native',
 'DR-2026-0055', '0xfdd79fccb22828b55236b93600cd3319d2255e84103a8c64ba314f00364c9038', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1201120, '2026-10-22T08:31:00Z', '0x752b770c23b79c502edd10aace3740d0c5cd4a7e80e9bc044f150a2604cc13a2', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-luca', 'org-gwm-lux', 'European Entity (Luxembourg) S.A.', 'LU',
 'UBGX Gold Token (Lux UAT)', 'Tokenized commodity / test asset', 'medium', 'Tier 2', 'PG-GOLD-LUX-UAT-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-uat-explorer.bank.internal/address/0xb29eddb1d3f7b9949f46bbf16b766f6cc836046e', '2026-10-22T08:40:00Z', '2026-10-26T06:00:00Z', 'Canary for the pending Luxembourg production request DR-2026-0051.'),
('ci-ubgx-besu-v2', 'ch-besu-prod', '0x13d1b05c7d8f66e5b46d1bdcb91a2aef7b7e6bd1', 'tpl-cmtat-230', 'logical', 'native',
 NULL, '0x123f88fac6c1db021ed8d2275214596c5fe2218309732fef1ed462e8c2dfa686', '0xb91057ad3a8a9931d14b955eea49cab749119c91', 'service',
 901220, '2024-11-05T14:20:00Z', NULL, '0xd695bd11dfc544bff305682566d68e43bb727a000c8bb1b5bbe1bc1e0cc0ee47', '0xd695bd11dfc544bff305682566d68e43bb727a000c8bb1b5bbe1bc1e0cc0ee47',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'retired', 'p-elena', 'org-gwm-com', 'Financial Institution AG', 'CH',
 'UBGX Gold Token v2', 'Tokenized commodity / retired', 'high', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x13d1b05c7d8f66e5b46d1bdcb91a2aef7b7e6bd1', '2024-11-05T14:30:00Z', '2026-03-18T11:00:00Z', 'Retired after migration to CMTAT 3.0.0. Supply redeemed and reserve released.'),
('ci-ubgx-eth', 'ch-eth-mainnet', '0x919d4f9416a4cf4b2b966eb4ac354e740dc094c6', 'tpl-cmtat-uups-300', 'logical', 'native',
 'DR-2026-0031', '0x25274113446fc9967ff356cc52345cfef6da98a040ae9fcfe006f246be79bfb4', '0x4f9803c6e4265d28cfe423007e54792c6bc490d2', 'service',
 21400000, '2026-02-11T08:05:00Z', '0x972c482a0d86076608c98029a53948e918837013d119f6bec7fd6acd8b275b28', '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b', '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b',
 'eip1967-uups', '0xf70be54517e4f2c31a25be1432572c56b77024a3', '0xf26274801325d20a15a830ce48cdae4f79fd907f', NULL,
 'active', 'p-elena', 'org-gwm-com', 'Financial Institution AG', 'CH',
 'UBGX Gold Token (Public)', 'Tokenized commodity / security token', 'critical', 'Tier 1', NULL,
 1, NULL, 'exact', 'Sourcify',
 'https://sourcify.dev/#/lookup/0x919d4f9416a4cf4b2b966eb4ac354e740dc094c6', '2026-02-11T08:30:00Z', '2026-10-26T06:05:00Z', 'Public distribution token. Upgrade admin is a 48h timelock controlled by a 3-of-5 Safe.'),
('ci-ubgx-eth-impl', 'ch-eth-mainnet', '0xf70be54517e4f2c31a25be1432572c56b77024a3', 'tpl-cmtat-uups-300', 'implementation', 'not_applicable',
 'DR-2026-0031', '0x25274113446fc9967ff356cc52345cfef6da98a040ae9fcfe006f246be79bfb4', '0x4f9803c6e4265d28cfe423007e54792c6bc490d2', 'service',
 21399990, '2026-02-11T07:58:00Z', NULL, '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b', '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b',
 'none', NULL, NULL, NULL,
 'active', 'p-elena', 'org-gwm-com', 'Financial Institution AG', 'CH',
 'UBGX Gold Token (Public) — implementation', 'Smart contract implementation', 'critical', 'Tier 1', NULL,
 0, NULL, 'exact', 'Sourcify',
 'https://sourcify.dev/#/lookup/0xf70be54517e4f2c31a25be1432572c56b77024a3', '2026-02-11T08:30:00Z', '2026-10-26T06:05:00Z', 'Implementation behind the public UBGX proxy. Not a product instance and excluded from deployment counts.'),
('ci-ubgx-eth-safe', 'ch-eth-mainnet', '0x7fa354d60cb6a121c1c5cd84616867d6eaa52897', 'tpl-safe-140', 'supporting', 'not_applicable',
 NULL, '0x78dc87b3d8f3207c0c638a9be0bab794668228e544a1c9dbd5494a86d4501e8c', '0x767c06dad1ddd4460722d033b43fc0a28c27a638', 'contract',
 21350000, '2025-09-12T09:00:00Z', NULL, '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4', '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4',
 'none', NULL, NULL, NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'UBGX Admin Safe 3-of-5', 'Multisig / governance', 'high', 'Tier 1', NULL,
 0, NULL, 'exact', 'Sourcify',
 'https://sourcify.dev/#/lookup/0x7fa354d60cb6a121c1c5cd84616867d6eaa52897', '2025-09-12T09:20:00Z', '2026-10-26T06:05:00Z', 'Controls the timelock. Five HSM-backed signer keys, threshold three.'),
('ci-ubgx-eth-timelock', 'ch-eth-mainnet', '0xf26274801325d20a15a830ce48cdae4f79fd907f', 'tpl-timelock-100', 'supporting', 'not_applicable',
 NULL, '0xcd0a923b5d54049f5a3f6d4a59434206d978e0c9a12df548e81717e4a257fcf9', '0x7fa354d60cb6a121c1c5cd84616867d6eaa52897', 'multisig',
 21350012, '2025-09-12T09:15:00Z', NULL, '0x62987977408a6e2a1cda748337bce75ad75b02110c5e2691ec9fc8c2f7e70afb', '0x62987977408a6e2a1cda748337bce75ad75b02110c5e2691ec9fc8c2f7e70afb',
 'none', NULL, NULL, NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'UBGX Timelock 48h', 'Governance / timelock', 'high', 'Tier 1', NULL,
 0, NULL, 'exact', 'Sourcify',
 'https://sourcify.dev/#/lookup/0xf26274801325d20a15a830ce48cdae4f79fd907f', '2025-09-12T09:30:00Z', '2026-10-26T06:05:00Z', '48-hour delay on upgrades and admin changes.'),
('ci-ruleengine-gold', 'ch-besu-prod', '0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25', 'tpl-ruleengine-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841205, '2026-03-18T10:47:00Z', NULL, '0xd53314af8045b38c8c31ba55894b96f36e78f136ccdfe056c85d33e2005737b1', '0xd53314af8045b38c8c31ba55894b96f36e78f136ccdfe056c85d33e2005737b1',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-sophie', 'org-cco', 'Financial Institution AG', 'CH',
 'Gold Transfer Rule Engine', 'Compliance rule engine', 'high', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', 'Deployed as part of the gold-token bundle. Rule engine changes are high-risk changes.'),
('ci-rule-maxholders', 'ch-besu-prod', '0x1617b7e542c029c30cc14b58a7395f114f538267', 'tpl-rule-maxholders-110', 'logical', 'not_applicable',
 'DR-2026-0042', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841206, '2026-03-18T10:47:00Z', NULL, '0x7ef6e2e40660aeb0e1b76cf8b4a40695450e429d279595bdbd9abd12b4bbccbd', '0x7ef6e2e40660aeb0e1b76cf8b4a40695450e429d279595bdbd9abd12b4bbccbd',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-sophie', 'org-cco', 'Financial Institution AG', 'CH',
 'Rule: Maximum Holders 500', 'Compliance rule', 'high', 'Tier 2', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x1617b7e542c029c30cc14b58a7395f114f538267', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', 'Current threshold 500. Change CR-2026-011 proposes 750.'),
('ci-rule-country', 'ch-besu-prod', '0x7caa0162ed0e97731f5eb3177d5299901f8cb836', 'tpl-rule-country-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841207, '2026-03-18T10:47:00Z', NULL, '0x128b8939927502564ec244e479df22e6d577f35ce1dc3ab7ef91ba395b68059f', '0x128b8939927502564ec244e479df22e6d577f35ce1dc3ab7ef91ba395b68059f',
 'none', NULL, '0x8e21784f4a55d8cf2c21db7511499874ea54905e', NULL,
 'active', 'p-sophie', 'org-cco', 'Financial Institution AG', 'CH',
 'Rule: Country Restriction CH/LU/LI', 'Compliance rule', 'high', 'Tier 2', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x7caa0162ed0e97731f5eb3177d5299901f8cb836', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', 'Control exception: admin is an EOA, not the Safe. Remediation open.'),
('ci-identity-gold', 'ch-besu-prod', '0xb6ddd943a75b0795132aa9ea0d3bdc07e0cd6dac', 'tpl-identity-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841208, '2026-03-18T10:48:00Z', NULL, '0x5173d7005e3e33a181eaa72807d1adb9edd1c03d1ff3ee4f15518ea402b7c02f', '0x5173d7005e3e33a181eaa72807d1adb9edd1c03d1ff3ee4f15518ea402b7c02f',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-sophie', 'org-cco', 'Financial Institution AG', 'CH',
 'Gold Identity Registry', 'Identity registry', 'high', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0xb6ddd943a75b0795132aa9ea0d3bdc07e0cd6dac', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', 'ONCHAINID references only; PII remains off-chain.'),
('ci-trusted-issuers', 'ch-besu-prod', '0x0107a206f8d272ad6e844238646f1337a0b8f6dd', 'tpl-trusted-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841209, '2026-03-18T10:48:00Z', NULL, '0x3b9710f8a4959f31b7d132812b624066d21d57f8a23f27770c2cba0b46b395f5', '0x3b9710f8a4959f31b7d132812b624066d21d57f8a23f27770c2cba0b46b395f5',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-sophie', 'org-cco', 'Financial Institution AG', 'CH',
 'Gold Trusted Issuers Registry', 'Identity registry', 'high', 'Tier 2', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x0107a206f8d272ad6e844238646f1337a0b8f6dd', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', NULL),
('ci-claim-topics', 'ch-besu-prod', '0xbf7c3cbf98bbd704414e4bd290af897858e54f1f', 'tpl-claim-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841210, '2026-03-18T10:48:00Z', NULL, '0x170aabb7129ffc6fe7a39c1fb766e8a6ec8d38fd8ebcf2d2e1208c973accfbd5', '0x170aabb7129ffc6fe7a39c1fb766e8a6ec8d38fd8ebcf2d2e1208c973accfbd5',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-sophie', 'org-cco', 'Financial Institution AG', 'CH',
 'Gold Claim Topics Registry', 'Identity registry', 'medium', 'Tier 2', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0xbf7c3cbf98bbd704414e4bd290af897858e54f1f', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', NULL),
('ci-oracle-gold', 'ch-besu-prod', '0x5cc834e94b9e430c229f48399ee13b4e6dc01f02', 'tpl-oracle-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0xe388c063c0ee7f625088ed0118ac51a7dee55bd0abfa377349c891c2e6f57cb4', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841212, '2026-03-18T10:49:00Z', NULL, '0xa74513cfec7f6f1618d4b0484e7ae90725adf1c49874d8ac138be21255d28282', '0xa74513cfec7f6f1618d4b0484e7ae90725adf1c49874d8ac138be21255d28282',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-marco', 'org-gwm-da', 'Financial Institution AG', 'CH',
 'Gold Price Oracle Adapter', 'Oracle adapter', 'high', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x5cc834e94b9e430c229f48399ee13b4e6dc01f02', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', 'Reads the XAU/USD Chainlink feed; heartbeat 1 hour, deviation 1%.'),
('ci-chainlink-xauusd', 'ch-eth-mainnet', '0xdd8b3feaaa6d1da135760aa503c1f10ab7ae577b', 'tpl-chainlink-feed-100', 'supporting', 'not_applicable',
 NULL, '0x421c1376f0a935e4277f030d2ed8ba54f05b1ec7a8e0128881e7abb8735a5a70', '0x8abb33a75858a934593ee4286dbe7117899a50bf', 'contract',
 19000000, '2024-01-15T00:00:00Z', NULL, '0x7bd8bb2e4e7b66a40cebbe6b5dc06b49e95ae0df75c6598082a91ad475500b95', '0x7bd8bb2e4e7b66a40cebbe6b5dc06b49e95ae0df75c6598082a91ad475500b95',
 'none', NULL, NULL, NULL,
 'active', 'p-marco', 'org-gwm-com', 'Chainlink Labs (external)', 'US/Global',
 'XAU/USD Chainlink Feed', 'External price oracle', 'high', 'Tier 1', NULL,
 0, NULL, 'partial', 'Chainlink',
 'https://etherscan.io/address/0xdd8b3feaaa6d1da135760aa503c1f10ab7ae577b', '2026-10-20T00:00:00Z', '2026-10-26T06:05:00Z', 'Third-party dependency. Source is not verified by the bank; monitor provider and feed heartbeat.'),
('ci-dvp-gold', 'ch-besu-prod', '0x3d6c1098232c31636aea11cb10c7124fab3d49d7', 'tpl-dvp-100', 'logical', 'not_applicable',
 NULL, '0x87f05396f4ec0487afd3308ba6a809aac190a5615ed240ef50379ef8a910681a', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1810000, '2026-05-12T12:10:00Z', NULL, '0x21ce350fcb275bcca4a2168b70c7a8f6ec6598c948714e3f0b3278b119648716', '0x21ce350fcb275bcca4a2168b70c7a8f6ec6598c948714e3f0b3278b119648716',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-marco', 'org-gwm-da', 'Financial Institution AG', 'CH',
 'Gold DvP Settlement', 'Delivery-versus-payment', 'critical', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x3d6c1098232c31636aea11cb10c7124fab3d49d7', '2026-05-12T12:20:00Z', '2026-10-26T06:00:00Z', 'Backfilled into the registry. Original CAB evidence is incomplete, so CTL-04 is an accepted exception.'),
('ci-chf-deposit', 'ch-besu-prod', '0xedf975de39cda7da80d85e1a2268315af7a48bb9', 'tpl-chf-deposit-100', 'logical', 'native',
 NULL, '0xda9ee3cbbe1c0e0341288d9a6fdf8e94f7d82bbacaf33bf6233745ccc78c8ef0', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1805000, '2026-04-02T09:00:00Z', NULL, '0x6222951902acb36083736c4fd16cf44e6929d4d8ed3a95f94f098e87747f5dd6', '0x6222951902acb36083736c4fd16cf44e6929d4d8ed3a95f94f098e87747f5dd6',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-marco', 'org-gwm-da', 'Financial Institution AG', 'CH',
 'CHF Deposit Token', 'Tokenized deposit', 'high', 'Tier 1', 'PG-CASH-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0xedf975de39cda7da80d85e1a2268315af7a48bb9', '2026-04-02T09:10:00Z', '2026-10-26T06:00:00Z', 'Cash leg for DvP. Not counted toward the gold reserve.'),
('ci-escrow-gold', 'ch-besu-prod', '0x47c26091b482f99a4fcfdce30d81a9528a2779c5', 'tpl-escrow-120', 'logical', 'not_applicable',
 NULL, '0x032d249d074fd0e217a13009266876af664e737767a8fb7434991324b278226e', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1820000, '2026-06-01T15:00:00Z', NULL, '0x334e84885b851c05dd1f7eebdd340b78c3f5dd8e3d140fa762596f77c70cec89', '0x334e84885b851c05dd1f7eebdd340b78c3f5dd8e3d140fa762596f77c70cec89',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-marco', 'org-gwm-da', 'Financial Institution AG', 'CH',
 'Gold Escrow', 'Value-holding escrow', 'high', 'Tier 2', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x47c26091b482f99a4fcfdce30d81a9528a2779c5', '2026-06-01T15:10:00Z', '2026-10-26T06:00:00Z', 'Bilateral collateral arrangement.'),
('ci-proof-of-reserve', 'ch-besu-prod', '0x5cf03dec96f3a57c6b257a8e2004b010a85861d3', 'tpl-por-100', 'logical', 'not_applicable',
 'DR-2026-0042', '0x7f83a0de546eda251a7859bb5cf002829d50f8a423d0658cd5d1316ae2a20347', '0xd8e353fe6dc0a761cdfe109fc52e637d898eda71', 'service',
 1841215, '2026-03-18T10:50:00Z', NULL, '0x4cba7853cd13a00f640249b9049b37e263b93d578c61070d4db745a7cd5d44a8', '0x4cba7853cd13a00f640249b9049b37e263b93d578c61070d4db745a7cd5d44a8',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-elena', 'org-gwm-com', 'Financial Institution AG', 'CH',
 'Gold Proof-of-Reserve Registry', 'Attestation registry', 'high', 'Tier 1', 'PG-GOLD-CH-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x5cf03dec96f3a57c6b257a8e2004b010a85861d3', '2026-03-18T10:55:00Z', '2026-10-26T06:00:00Z', 'Anchors reserve hashes and coverage, not bar lists.'),
('ci-factory-besu', 'ch-besu-prod', '0xd8c048a9d8ae7cd05b98b93a0214c8f792167439', 'tpl-factory-100', 'supporting', 'not_applicable',
 NULL, '0xe13870ad35c137ea1a8dc8bdff6428d3011c13500ec0c32065edc86a94aca8d3', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig',
 1750000, '2025-11-20T10:00:00Z', NULL, '0x8bd8d766ca3e3eb5864d9b1323192e21ff3c88ed582d91f5977c6447601ea363', '0x8bd8d766ca3e3eb5864d9b1323192e21ff3c88ed582d91f5977c6447601ea363',
 'none', NULL, '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'Tokenization Factory', 'Deployment factory', 'high', 'Tier 1', 'PG-PLATFORM-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0xd8c048a9d8ae7cd05b98b93a0214c8f792167439', '2025-11-20T10:10:00Z', '2026-10-26T06:00:00Z', 'Only allowlisted deployer addresses may call the factory.'),
('ci-multicall-besu', 'ch-besu-prod', '0x010a7c53e35a55ec507a00ebbe0fa98283c3c5a2', 'tpl-multicall-300', 'supporting', 'not_applicable',
 NULL, '0xd91731e8d44aeae6c57fc35326aa364cdcbfd917412b2d9a2fdb8be8a4feb0f8', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig',
 1750010, '2025-11-20T10:05:00Z', NULL, '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30', '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30',
 'none', NULL, NULL, NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'Multicall3 (Ledger)', 'Shared utility', 'low', 'Tier 3', 'PG-PLATFORM-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0x010a7c53e35a55ec507a00ebbe0fa98283c3c5a2', '2025-11-20T10:10:00Z', '2026-10-26T06:00:00Z', 'No privileged roles and no value custody.'),
('ci-multicall-eth', 'ch-eth-mainnet', '0x5da78ba88f17547ead0c4b119ea9056e43bad249', 'tpl-multicall-300', 'supporting', 'not_applicable',
 NULL, '0xd91731e8d44aeae6c57fc35326aa364cdcbfd917412b2d9a2fdb8be8a4feb0f8', '0x7fa354d60cb6a121c1c5cd84616867d6eaa52897', 'multisig',
 21350100, '2025-09-12T09:40:00Z', NULL, '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30', '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30',
 'none', NULL, NULL, NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'Multicall3 (Public)', 'Shared utility', 'low', 'Tier 3', NULL,
 0, NULL, 'exact', 'Sourcify',
 'https://sourcify.dev/#/lookup/0x5da78ba88f17547ead0c4b119ea9056e43bad249', '2025-09-12T09:50:00Z', '2026-10-26T06:05:00Z', NULL),
('ci-safe-besu', 'ch-besu-prod', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'tpl-safe-140', 'supporting', 'not_applicable',
 NULL, '0x78dc87b3d8f3207c0c638a9be0bab794668228e544a1c9dbd5494a86d4501e8c', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig',
 1700000, '2025-11-20T09:30:00Z', NULL, '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4', '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4',
 'none', NULL, NULL, NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'Ledger Admin Safe 3-of-5', 'Multisig / governance', 'high', 'Tier 1', 'PG-PLATFORM-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0xc3b5e332056d18c4febe491b0a27049887df48dd', '2025-11-20T09:40:00Z', '2026-10-26T06:00:00Z', 'Controls admin, minter and pauser roles on the ledger.'),
('ci-timelock-besu', 'ch-besu-prod', '0xaf96c96d50ad344c528f127c1c95034201f68f3c', 'tpl-timelock-100', 'supporting', 'not_applicable',
 NULL, '0xcd0a923b5d54049f5a3f6d4a59434206d978e0c9a12df548e81717e4a257fcf9', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig',
 1700010, '2025-11-20T09:45:00Z', NULL, '0x62987977408a6e2a1cda748337bce75ad75b02110c5e2691ec9fc8c2f7e70afb', '0x62987977408a6e2a1cda748337bce75ad75b02110c5e2691ec9fc8c2f7e70afb',
 'none', NULL, NULL, NULL,
 'active', 'p-nina', 'org-cio-plt', 'Financial Institution AG', 'CH',
 'Ledger Timelock 48h', 'Governance / timelock', 'high', 'Tier 1', 'PG-PLATFORM-01',
 0, NULL, 'exact', 'Internal bytecode manifest',
 'https://ledger-explorer.bank.internal/address/0xaf96c96d50ad344c528f127c1c95034201f68f3c', '2025-11-20T09:50:00Z', '2026-10-26T06:00:00Z', NULL);

UPDATE contract_instance SET supersedes_id = 'ci-ubgx-besu-v2' WHERE id = 'ci-ubgx-besu';

UPDATE contract_instance SET signing_identity_id = 'si-eth-service' WHERE id IN ('ci-ubgx-eth', 'ci-ubgx-eth-impl');
UPDATE contract_instance SET signing_identity_id = 'si-timelock-eth' WHERE id = 'ci-ubgx-eth-timelock';
UPDATE contract_instance SET signing_identity_id = 'si-safe-eth' WHERE id IN ('ci-ubgx-eth-safe', 'ci-multicall-eth');
UPDATE contract_instance SET signing_identity_id = 'si-besu-service' WHERE id IN (
    'ci-ubgx-besu', 'ci-ruleengine-gold', 'ci-rule-maxholders', 'ci-rule-country',
    'ci-identity-gold', 'ci-trusted-issuers', 'ci-claim-topics', 'ci-oracle-gold',
    'ci-dvp-gold', 'ci-chf-deposit', 'ci-escrow-gold', 'ci-proof-of-reserve'
);
UPDATE contract_instance SET signing_identity_id = 'si-besu-uat-service' WHERE id IN ('ci-ubgx-besu-uat', 'ci-ubgx-lux-uat');
UPDATE contract_instance SET signing_identity_id = 'si-old-besu' WHERE id = 'ci-ubgx-besu-v2';
UPDATE contract_instance SET signing_identity_id = 'si-safe-besu' WHERE id IN (
    'ci-safe-besu', 'ci-timelock-besu', 'ci-factory-besu', 'ci-multicall-besu'
);
UPDATE contract_instance SET signing_identity_id = 'si-chainlink' WHERE id = 'ci-chainlink-xauusd';

INSERT INTO reserve_pool (id, pool_code, description, asset, custodian, legal_entity, vault_location) VALUES
('rp-gold-public', 'XAU-CH-PUB', 'Public UBGX gold allocation', 'XAU', 'Precious Metals AG', 'Financial Institution AG', 'Zurich Vault 2'),
('rp-gold-ledger', 'XAU-CH-LED', 'Private-banking UBGX gold allocation', 'XAU', 'Precious Metals AG', 'Financial Institution AG', 'Zurich Vault 3'),
('rp-gold-uat-ch', 'XAU-UAT-CH', 'UAT test pool CH', 'XAU', 'Test Vault (UAT)', 'Financial Institution AG', 'UAT'),
('rp-gold-uat-lux', 'XAU-UAT-LUX', 'UAT test pool LU', 'XAU', 'Test Vault (UAT)', 'European Entity (Luxembourg) S.A.', 'UAT');

INSERT INTO token_metadata (instance_id, token_name, symbol, decimals, total_supply, asset_class, underlying_asset, custodian, isin, currency, supply_scope, counts_toward_reserve, kyc_required, transfer_restrictions, proof_of_reserve_uri, redemption_terms_uri, valuation_source) VALUES
('ci-ubgx-besu', 'UBGX Gold Token (Ledger)', 'UBGX', 4, 32500.0, 'Tokenized commodity', 'XAU', 'Precious Metals AG', 'CH0000000001', 'XAU', 'Private-banking ledger distribution', 1, 1, 'CMTAT RuleEngine + ERC-3643 identity registry + country rule', 'dataroom://gold/proof-of-reserve-2026-10.pdf', 'dataroom://gold/terms-v4.pdf', 'LBMA Gold Price PM, converted to CHF; oracle adapter'),
('ci-ubgx-besu-uat', 'UBGX Gold Token (UAT)', 'UBGX', 4, 1000.0, 'Tokenized commodity / test', 'XAU', 'Test Vault (UAT)', NULL, 'XAU', 'UAT only', 0, 1, 'CMTAT RuleEngine', NULL, 'dataroom://gold/terms-uat.pdf', 'Test oracle'),
('ci-ubgx-lux-uat', 'UBGX Gold Token (Lux UAT)', 'UBGXL', 4, 500.0, 'Tokenized commodity / test', 'XAU', 'Test Vault (UAT)', NULL, 'XAU', 'UAT only', 0, 1, 'CMTAT RuleEngine', NULL, 'dataroom://gold/terms-lux-uat.pdf', 'Test oracle'),
('ci-ubgx-besu-v2', 'UBGX Gold Token v2', 'UBGX', 4, 0.0, 'Tokenized commodity / retired', 'XAU', 'Precious Metals AG', NULL, 'XAU', 'Retired and redeemed', 0, 1, 'Legacy allowlist', NULL, 'dataroom://gold/terms-v3.pdf', 'Legacy valuation'),
('ci-ubgx-eth', 'Gold Token', 'UBGX', 4, 92500.0, 'Tokenized commodity / security', 'XAU', 'Precious Metals AG', 'CH0000000001', 'XAU', 'Public distribution', 1, 1, 'CMTAT RuleEngine, allowlist and investor eligibility', 'dataroom://gold/proof-of-reserve-2026-10.pdf', 'dataroom://gold/terms-v4.pdf', 'LBMA Gold Price PM, converted to CHF; oracle adapter'),
('ci-chf-deposit', 'Financial Institution CHF Deposit Token', 'CHFD', 2, 4500000.0, 'Tokenized deposit', 'CHF', 'Financial Institution AG', NULL, 'CHF', 'Permissioned cash leg', 0, 1, 'Permissioned allowlist', NULL, 'dataroom://cash/deposit-terms.pdf', '1:1 CHF deposit');

UPDATE token_metadata SET reserve_pool_id = 'rp-gold-public' WHERE instance_id = 'ci-ubgx-eth';
UPDATE token_metadata SET reserve_pool_id = 'rp-gold-ledger' WHERE instance_id = 'ci-ubgx-besu';
UPDATE token_metadata SET reserve_pool_id = 'rp-gold-uat-ch' WHERE instance_id = 'ci-ubgx-besu-uat';
UPDATE token_metadata SET reserve_pool_id = 'rp-gold-uat-lux' WHERE instance_id = 'ci-ubgx-lux-uat';

INSERT INTO compliance_profile (
    instance_id, regulatory_classification, mica_type, instrument_id, fungibility_group,
    prospectus_ref, legal_structure, holder_claim_type, segregation_basis, insolvency_remoteness,
    custody_agreement_ref, legal_title_ref, aml_risk_rating, client_eligibility,
    sanctions_screening, travel_rule, distribution_countries, investor_type, target_market,
    dpia_ref, dpo_assessment, onchain_pii_risk, privacy_group_members, dora_register_ref,
    ict_third_party_ref, exit_plan, concentration_risk, redemption_rights, redemption_sla,
    complaint_handling, records_retention, tax_treatment, status, last_reviewed_at, reviewed_by
) VALUES
('ci-ubgx-eth', 'Tokenized commodity / security token (CH)', 'Outside MiCA / MiFID security-token review', 'CH0000000001', 'UBGX-CH', 'doc-prospectus', 'Issuer SPV with allocated gold claim', 'Beneficial claim against issuer and allocated bars', 'Allocated, segregated, tri-party custody', 'Legal opinion pending - gap', 'custody-agreement-v3', 'doc-legal-eth', 'high', 'Professional / eligible counterparties; no retail without appropriateness', 'Daily vendor screening; on-chain blocklist evidence pending', 'Off-chain originator/beneficiary and VASP data; not evidenced', 'CH,LU,LI', 'Professional / eligible', 'Digital gold, wealth management', 'DPIA-GOLD-001', 'Conditional - public-chain metadata assessment open', 'High - public addresses and amounts are permanent', 'Public chain; no privacy group', 'DORA-GOLD-001', 'Chainlink, custodian, Besu consortium, private cloud', 'Pause minting; secondary oracle; legal transfer of bars', 'Single custodian and single public chain', 'Monthly redemption; 5 business days; fees per terms', 'T+5 business days; 1% buffer', 'complaints@example.com / 30 days / ombudsman', '10 years; legal hold supported', 'CH withholding/transfer tax review pending', 'partial', '2026-10-24', 'p-sophie'),
('ci-ubgx-besu', 'Tokenized commodity / permissioned security token (CH)', 'Outside MiCA / permissioned security-token review', 'CH0000000001', 'UBGX-CH', 'doc-prospectus', 'Issuer SPV with allocated gold claim', 'Beneficial claim against issuer and allocated bars', 'Allocated, segregated, tri-party custody', 'Legal opinion pending - gap', 'custody-agreement-v3', 'doc-legal-eth', 'high', 'Professional / eligible counterparties', 'Daily vendor screening; privacy-group participation control', 'Participant-level DvP data; travel rule open', 'CH,LU,LI', 'Professional / eligible', 'Private-banking digital gold', 'DPIA-GOLD-001', 'Conditional - privacy-group membership review open', 'Medium - permissioned, but consortium members see state', 'Financial Institution AG, custodian, auditor', 'DORA-GOLD-001', 'Besu consortium, custodian, auditor, private cloud', 'Transfer bars or migrate ledger; replay final state', 'Single consortium and custodian', 'Monthly redemption; 5 business days', 'T+5 business days; 1% buffer', 'complaints@example.com / 30 days', '10 years; legal hold supported', 'CH withholding/transfer tax review pending', 'partial', '2026-10-24', 'p-sophie'),
('ci-ubgx-besu-uat', 'Test asset - not for client distribution', NULL, NULL, 'UBGX-UAT', NULL, 'UAT test token', 'No client claim', 'No reserve; test vault only', 'Not applicable', NULL, NULL, 'low', 'Internal test only', 'Synthetic data only', 'Not applicable', 'UAT only', 'Internal', 'Testing', 'DPIA-TEST-001', 'Approved for synthetic data only', 'Low - synthetic addresses', 'PG-GOLD-UAT-01', 'Not applicable', 'Besu UAT', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '90 days', 'N/A', 'gap', '2026-10-22', 'p-jonas'),
('ci-ubgx-lux-uat', 'Test asset - not for client distribution', NULL, NULL, 'UBGX-UAT', NULL, 'UAT test token (Luxembourg)', 'No client claim', 'No reserve; test vault only', 'Not applicable', NULL, NULL, 'low', 'Internal test only', 'Synthetic data only', 'Not applicable', 'UAT only', 'Internal', 'Testing', 'DPIA-TEST-001', 'Approved for synthetic data only', 'Low - synthetic addresses', 'PG-GOLD-LUX-UAT-01', 'Not applicable', 'Besu UAT', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '90 days', 'N/A', 'gap', '2026-10-22', 'p-jonas'),
('ci-chf-deposit', 'Tokenized deposit / cash leg', 'MiCA EMT / deposit-token review', 'CH0000000002', 'CHFD', 'dataroom://cash/deposit-terms.pdf', 'Bank deposit claim', 'Deposit claim against Financial Institution AG', 'Balance-sheet deposit; not segregated', 'Deposit insurance / priority review', NULL, NULL, 'high', 'Permissioned institutional clients', 'Daily vendor screening', 'DvP participant and VASP data', 'CH', 'Institutional', 'DvP cash leg', 'DPIA-CASH-001', 'Approved', 'Medium - permissioned ledger', 'PG-CASH-CH-01', 'DORA-CASH-001', 'Besu consortium, private cloud', 'Repatriate balances; migrate ledger', 'Single bank and ledger', 'Same-day redemption on request', 'T+0', 'complaints@example.com / 30 days', '10 years', 'CH deposit/tax treatment reviewed', 'partial', '2026-10-20', 'p-sophie'),
('ci-dvp-gold', 'Settlement contract - not a token', NULL, NULL, NULL, NULL, 'DvP agent / settlement finality', 'No client claim; operational contract', 'N/A', 'N/A', NULL, 'doc-audit-dvp', 'high', 'Institutional participants', 'Participant screening', 'Originator/beneficiary data per DvP', 'CH,LU', 'Institutional', 'Atomic settlement', 'DPIA-DVP-001', 'Approved', 'Medium - permissioned ledger', 'PG-GOLD-CH-01', 'DORA-SETTLE-001', 'Besu consortium, private cloud', 'Replay final state; manual settlement fallback', 'Single ledger and cash leg', 'N/A', '300 seconds', 'complaints@example.com / 30 days', '10 years', 'Transfer pricing review', 'partial', '2026-10-20', 'p-daniel'),
('ci-escrow-gold', 'Escrow / collateral contract', NULL, NULL, NULL, NULL, 'Bilateral escrow', 'Conditional claim on escrowed gold', 'Segregated escrow account', 'Legal opinion gap', NULL, NULL, 'high', 'Institutional counterparties', 'Counterparty screening', 'Not applicable', 'CH', 'Institutional', 'Collateral arrangement', 'DPIA-ESCROW-001', 'Conditional', 'Medium - permissioned ledger', 'PG-GOLD-CH-01', 'DORA-ESCROW-001', 'Besu consortium, private cloud', 'Release or transfer escrow; legal escalation', 'Single counterparty', 'Per contract', 'Per contract', 'complaints@example.com / 30 days', '10 years', 'Per contract', 'gap', '2026-10-20', 'p-daniel');

INSERT INTO instance_ict (instance_id, provider_id, dependency_type, critical, evidence_uri) VALUES
('ci-ubgx-eth', 'ict-chainlink', 'price feed', 1, 'evidence://ict/ubgx-eth/chainlink'),
('ci-ubgx-eth', 'ict-custodian', 'allocated gold custody', 1, 'evidence://ict/ubgx-eth/custodian'),
('ci-ubgx-eth', 'ict-auditor', 'reserve attestation', 1, 'evidence://ict/ubgx-eth/auditor'),
('ci-ubgx-eth', 'ict-besu', 'rule engine network dependency', 1, 'evidence://ict/ubgx-eth/besu-rule-engine'),
('ci-ubgx-eth', 'ict-cloud', 'hosting and HSM', 1, 'evidence://ict/ubgx-eth/cloud'),
('ci-ubgx-besu', 'ict-besu', 'ledger operation', 1, 'evidence://ict/ubgx-besu/ledger'),
('ci-ubgx-besu', 'ict-custodian', 'allocated gold custody', 1, 'evidence://ict/ubgx-besu/custodian'),
('ci-ubgx-besu', 'ict-auditor', 'reserve attestation', 1, 'evidence://ict/ubgx-besu/auditor'),
('ci-ubgx-besu', 'ict-cloud', 'hosting and HSM', 1, 'evidence://ict/ubgx-besu/cloud'),
('ci-ubgx-besu-uat', 'ict-besu', 'ledger operation', 1, 'evidence://ict/uat/ledger'),
('ci-chf-deposit', 'ict-besu', 'ledger operation', 1, 'evidence://ict/chf/ledger'),
('ci-chf-deposit', 'ict-cloud', 'hosting and HSM', 1, 'evidence://ict/chf/cloud'),
('ci-dvp-gold', 'ict-besu', 'ledger operation', 1, 'evidence://ict/dvp/ledger'),
('ci-dvp-gold', 'ict-cloud', 'hosting and HSM', 1, 'evidence://ict/dvp/cloud'),
('ci-oracle-gold', 'ict-chainlink', 'price feed', 1, 'evidence://ict/oracle/chainlink'),
('ci-chainlink-xauusd', 'ict-chainlink', 'external oracle', 1, 'evidence://ict/chainlink/external'),
('ci-escrow-gold', 'ict-besu', 'ledger operation', 1, 'evidence://ict/escrow/ledger');

INSERT INTO reserve_snapshot (id, instance_id, pool_id, as_of, token_supply, gold_grams, coverage_ratio, bars_count, auditor, report_document_id, is_current, verified, notes) VALUES
('rs-eth-2026-10', 'ci-ubgx-eth', 'rp-gold-public', '2026-10-24', 92500.0, 93425.0, 1.0100, 8, 'Helvetia Assurance AG', 'doc-por', 1, 1, 'Allocated, insured LBMA Good Delivery bars in Zurich.'),
('rs-besu-2026-10', 'ci-ubgx-besu', 'rp-gold-ledger', '2026-10-24', 32500.0, 32825.0, 1.0100, 3, 'Helvetia Assurance AG', 'doc-por', 1, 1, 'Separate allocation for the private-banking pool.'),
('rs-eth-2026-09', 'ci-ubgx-eth', 'rp-gold-public', '2026-09-24', 90000.0, 90450.0, 1.0050, 8, 'Helvetia Assurance AG', 'doc-por', 0, 1, 'Prior month comparison.'),
('rs-uat-2026-10', 'ci-ubgx-besu-uat', 'rp-gold-uat-ch', '2026-10-24', 1000.0, 1000.0, 1.0000, 0, 'Internal test', NULL, 1, 0, 'Test vault; not real gold.'),
('rs-lux-uat-2026-10', 'ci-ubgx-lux-uat', 'rp-gold-uat-lux', '2026-10-24', 500.0, 500.0, 1.0000, 0, 'Internal test', NULL, 1, 0, 'Test vault; not real gold.');

INSERT INTO gold_bar (id, instance_id, serial_number, refinery, purity, weight_grams, vault, vault_location, status, last_audit_at) VALUES
('bar-01', 'ci-ubgx-eth', 'CH-2026-0001', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-02', 'ci-ubgx-eth', 'CH-2026-0002', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-03', 'ci-ubgx-eth', 'CH-2026-0003', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-04', 'ci-ubgx-eth', 'CH-2026-0004', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-05', 'ci-ubgx-besu', 'CH-2026-0101', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 3', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-06', 'ci-ubgx-besu', 'CH-2026-0102', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 3', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-07', 'ci-ubgx-besu', 'CH-2026-0103', 'Alpine Refining AG', '999.9', 7825.0, 'Zurich Vault 3', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-08', 'ci-ubgx-eth', 'CH-2026-0005', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-09', 'ci-ubgx-eth', 'CH-2026-0006', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-10', 'ci-ubgx-eth', 'CH-2026-0007', 'Alpine Refining AG', '999.9', 12500.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24'),
('bar-11', 'ci-ubgx-eth', 'CH-2026-0008', 'Alpine Refining AG', '999.9', 5925.0, 'Zurich Vault 2', 'Zurich, CH', 'allocated', '2026-10-24');

INSERT INTO contract_link (from_instance_id, to_instance_id, relation, confidence, valid_from, evidence_tx, notes) VALUES
('ci-ubgx-eth', 'ci-ubgx-eth-impl', 'delegates_to', 'confirmed', '2026-02-11', '0x25274113446fc9967ff356cc52345cfef6da98a040ae9fcfe006f246be79bfb4', 'EIP-1967 implementation slot.'),
('ci-ubgx-eth', 'ci-ubgx-eth-timelock', 'admin_controlled_by', 'confirmed', '2026-02-11', '0x43cfbc9bef05b1e6d9e77ff82368ecc78f565d5e0c647aa26bf0b576fcdbba40', 'UPGRADER_ROLE and DEFAULT_ADMIN_ROLE.'),
('ci-ubgx-eth-timelock', 'ci-ubgx-eth-safe', 'admin_controlled_by', 'confirmed', '2025-09-12', '0xcd0a923b5d54049f5a3f6d4a59434206d978e0c9a12df548e81717e4a257fcf9', 'Safe is the only proposer/executor.'),
('ci-ubgx-besu', 'ci-ruleengine-gold', 'uses_rule_engine', 'confirmed', '2026-03-18', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', 'CMTAT RuleEngine address.'),
('ci-ruleengine-gold', 'ci-rule-maxholders', 'contains_rule', 'confirmed', '2026-03-18', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', 'Rule 1 of 2.'),
('ci-ruleengine-gold', 'ci-rule-country', 'contains_rule', 'confirmed', '2026-03-18', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', 'Rule 2 of 2.'),
('ci-ubgx-besu', 'ci-identity-gold', 'uses_identity_registry', 'confirmed', '2026-03-18', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', 'ERC-3643 identity registry.'),
('ci-identity-gold', 'ci-trusted-issuers', 'reads_trusted_issuers', 'confirmed', '2026-03-18', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', NULL),
('ci-identity-gold', 'ci-claim-topics', 'reads_claim_topics', 'confirmed', '2026-03-18', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', NULL),
('ci-ubgx-besu', 'ci-oracle-gold', 'prices_from', 'confirmed', '2026-03-18', '0xe388c063c0ee7f625088ed0118ac51a7dee55bd0abfa377349c891c2e6f57cb4', NULL),
('ci-oracle-gold', 'ci-chainlink-xauusd', 'reads_price_feed', 'confirmed', '2026-03-18', '0xe388c063c0ee7f625088ed0118ac51a7dee55bd0abfa377349c891c2e6f57cb4', 'Cross-chain dependency: Besu adapter consumes a public Ethereum feed.'),
('ci-ubgx-besu', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-03-18', '0xa041e1ef3baad1b891259aca20a0eba20f5f0fea22544f43a136eb6650099895', 'Safe holds DEFAULT_ADMIN_ROLE, MINTER_ROLE and PAUSER_ROLE.'),
('ci-ruleengine-gold', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-03-18', '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', NULL),
('ci-identity-gold', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-03-18', '0x3247a065fc5697455d64c8be6724ff435459124f695f7946b2fd3c7e274e2427', NULL),
('ci-dvp-gold', 'ci-ubgx-besu', 'settles_with', 'confirmed', '2026-05-12', '0x87f05396f4ec0487afd3308ba6a809aac190a5615ed240ef50379ef8a910681a', 'Delivery leg.'),
('ci-dvp-gold', 'ci-chf-deposit', 'settles_with', 'confirmed', '2026-05-12', '0x87f05396f4ec0487afd3308ba6a809aac190a5615ed240ef50379ef8a910681a', 'Payment leg.'),
('ci-escrow-gold', 'ci-ubgx-besu', 'collateralised_by', 'confirmed', '2026-06-01', '0x032d249d074fd0e217a13009266876af664e737767a8fb7434991324b278226e', NULL),
('ci-ubgx-besu', 'ci-factory-besu', 'deployed_by_factory', 'inferred', '2026-03-18', '0xe13870ad35c137ea1a8dc8bdff6428d3011c13500ec0c32065edc86a94aca8d3', 'Factory event matches the init-code hash.'),
('ci-ubgx-lux-uat', 'ci-factory-besu', 'deployed_by_factory', 'confirmed', '2026-10-22', '0x26d9518425cfd2bbac15a81cd9b40027aa5d351b0ce71876ef609cc355a18b5e', 'CREATE2 clone.'),
('ci-ubgx-besu', 'ci-ubgx-besu-v2', 'supersedes', 'confirmed', '2026-03-18', '0x212b490d6930d8c0947ff47cc4175a4fe2dd0913b7c11de41f10668564bd9c39', 'Migration completed; v2 supply redeemed.'),
('ci-ubgx-besu', 'ci-proof-of-reserve', 'attested_by', 'confirmed', '2026-03-18', '0xfa924c68d5464593b5329b04e665b22bfed8e8bee6a6c532341ae98e14264537', 'Reserve attestation anchored on-chain.'),
('ci-oracle-gold', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-03-18', '0xe388c063c0ee7f625088ed0118ac51a7dee55bd0abfa377349c891c2e6f57cb4', NULL),
('ci-dvp-gold', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-05-12', '0x87f05396f4ec0487afd3308ba6a809aac190a5615ed240ef50379ef8a910681a', NULL),
('ci-chf-deposit', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-04-02', '0xda9ee3cbbe1c0e0341288d9a6fdf8e94f7d82bbacaf33bf6233745ccc78c8ef0', NULL),
('ci-escrow-gold', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-06-01', '0x032d249d074fd0e217a13009266876af664e737767a8fb7434991324b278226e', NULL),
('ci-proof-of-reserve', 'ci-safe-besu', 'admin_controlled_by', 'confirmed', '2026-03-18', '0x7f83a0de546eda251a7859bb5cf002829d50f8a423d0658cd5d1316ae2a20347', NULL);

INSERT INTO instance_role (instance_id, role_name, holder_address, holder_type, holder_instance_id, person_id, status, assigned_at, source_event_id) VALUES
('ci-ubgx-eth', 'DEFAULT_ADMIN_ROLE', '0xf26274801325d20a15a830ce48cdae4f79fd907f', 'timelock', 'ci-ubgx-eth-timelock', NULL, 'active', '2026-02-11', NULL),
('ci-ubgx-eth', 'UPGRADER_ROLE', '0xf26274801325d20a15a830ce48cdae4f79fd907f', 'timelock', 'ci-ubgx-eth-timelock', NULL, 'active', '2026-02-11', NULL),
('ci-ubgx-eth', 'MINTER_ROLE', '0x7fa354d60cb6a121c1c5cd84616867d6eaa52897', 'multisig', 'ci-ubgx-eth-safe', NULL, 'active', '2026-02-11', NULL),
('ci-ubgx-eth', 'PAUSER_ROLE', '0x7fa354d60cb6a121c1c5cd84616867d6eaa52897', 'multisig', 'ci-ubgx-eth-safe', NULL, 'active', '2026-02-11', NULL),
('ci-ubgx-besu', 'DEFAULT_ADMIN_ROLE', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-ubgx-besu', 'MINTER_ROLE', '0x21da7162938af12d11ddb53851ddd40e306c50fd', 'hsm', NULL, 'p-nina', 'active', '2026-03-18', NULL),
('ci-ubgx-besu', 'PAUSER_ROLE', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-ubgx-besu', 'RULE_ENGINE_ADMIN', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-ruleengine-gold', 'RULE_ADMIN', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-rule-maxholders', 'RULE_ADMIN', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-rule-country', 'OWNER', '0x8e21784f4a55d8cf2c21db7511499874ea54905e', 'eoa', NULL, 'p-sophie', 'active', '2026-03-18', NULL),
('ci-identity-gold', 'AGENT', '0x4d7370f144045094e1d9d89e3e56bb614801177c', 'hsm', NULL, 'p-sophie', 'active', '2026-03-18', NULL),
('ci-trusted-issuers', 'OWNER', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-claim-topics', 'OWNER', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-oracle-gold', 'FEED_ADMIN', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-03-18', NULL),
('ci-oracle-gold', 'PRICE_UPDATER', '0x4d7370f144045094e1d9d89e3e56bb614801177c', 'hsm', NULL, 'p-marco', 'active', '2026-03-18', NULL),
('ci-proof-of-reserve', 'ATTESTOR', '0x4d7370f144045094e1d9d89e3e56bb614801177c', 'hsm', NULL, 'p-elena', 'active', '2026-03-18', NULL),
('ci-dvp-gold', 'SETTLER_ROLE', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-05-12', NULL),
('ci-dvp-gold', 'OPERATOR_ROLE', '0x4d7370f144045094e1d9d89e3e56bb614801177c', 'hsm', NULL, 'p-marco', 'active', '2026-05-12', NULL),
('ci-chf-deposit', 'MINTER_ROLE', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-04-02', NULL),
('ci-chf-deposit', 'PAUSER_ROLE', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-04-02', NULL),
('ci-escrow-gold', 'ARBITER', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 'multisig', 'ci-safe-besu', NULL, 'active', '2026-06-01', NULL);

INSERT INTO instance_parameter (id, instance_id, name, value, value_hash, source, is_sensitive) VALUES
('ip-01', 'ci-ubgx-besu', 'tokenName', 'UBGX Gold Token (Ledger)', NULL, 'constructor', 0),
('ip-02', 'ci-ubgx-besu', 'tokenSymbol', 'UBGX', NULL, 'constructor', 0),
('ip-03', 'ci-ubgx-besu', 'decimals', '4', NULL, 'constructor', 0),
('ip-04', 'ci-ubgx-besu', 'maxSupply', '500000000', NULL, 'constructor', 0),
('ip-05', 'ci-ubgx-besu', 'ruleEngine', '0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25', NULL, 'constructor', 0),
('ip-06', 'ci-ubgx-besu', 'admin', '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL, 'constructor', 0),
('ip-07', 'ci-ubgx-besu', 'termsURI', 'ipfs://bafybeigoldterms', '0xd5fb26c6e056a618ec20b07c3503da0aa44c14d97adbf8e631899dc88336d10f', 'constructor', 0),
('ip-08', 'ci-ubgx-eth', 'tokenName', 'Gold Token', NULL, 'initializer', 0),
('ip-09', 'ci-ubgx-eth', 'tokenSymbol', 'UBGX', NULL, 'initializer', 0),
('ip-10', 'ci-ubgx-eth', 'decimals', '4', NULL, 'initializer', 0),
('ip-11', 'ci-ubgx-eth', 'maxSupply', '1250000000', NULL, 'initializer', 0),
('ip-12', 'ci-ubgx-eth', 'ruleEngine', '0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25', NULL, 'initializer', 0),
('ip-13', 'ci-ubgx-eth', 'admin', '0xf26274801325d20a15a830ce48cdae4f79fd907f', NULL, 'initializer', 0),
('ip-14', 'ci-ubgx-eth', 'termsURI', 'ipfs://bafybeigoldterms', '0xd5fb26c6e056a618ec20b07c3503da0aa44c14d97adbf8e631899dc88336d10f', 'initializer', 0),
('ip-15', 'ci-rule-maxholders', 'maxHolders', '500', NULL, 'constructor', 0),
('ip-16', 'ci-rule-maxholders', 'admin', '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL, 'constructor', 0),
('ip-17', 'ci-rule-country', 'allowedCountries', 'CH,LU,LI', NULL, 'constructor', 0),
('ip-18', 'ci-rule-country', 'admin', '0x8e21784f4a55d8cf2c21db7511499874ea54905e', NULL, 'constructor', 0),
('ip-19', 'ci-oracle-gold', 'feed', '0xdd8b3feaaa6d1da135760aa503c1f10ab7ae577b', NULL, 'constructor', 0),
('ip-20', 'ci-oracle-gold', 'heartbeatSeconds', '3600', NULL, 'constructor', 0),
('ip-21', 'ci-oracle-gold', 'deviationBps', '100', NULL, 'constructor', 0),
('ip-22', 'ci-dvp-gold', 'assetToken', '0x46009f357c42ca5895de915a469cbb56b760411e', NULL, 'constructor', 0),
('ip-23', 'ci-dvp-gold', 'paymentToken', '0xedf975de39cda7da80d85e1a2268315af7a48bb9', NULL, 'constructor', 0),
('ip-24', 'ci-dvp-gold', 'settlementWindow', '300', NULL, 'constructor', 0),
('ip-25', 'ci-chf-deposit', 'tokenName', 'Financial Institution CHF Deposit Token', NULL, 'constructor', 0),
('ip-26', 'ci-chf-deposit', 'tokenSymbol', 'CHFD', NULL, 'constructor', 0),
('ip-27', 'ci-chf-deposit', 'decimals', '2', NULL, 'constructor', 0),
('ip-28', 'ci-chf-deposit', 'admin', '0xc3b5e332056d18c4febe491b0a27049887df48dd', NULL, 'constructor', 0),
('ip-29', 'ci-ubgx-eth', 'implementation', '0xf70be54517e4f2c31a25be1432572c56b77024a3', NULL, 'admin_call', 0);

INSERT INTO document (id, object_type, object_id, doc_type, title, uri, sha256, version, valid_from, valid_to, onchain_anchor_tx, confidentiality, uploaded_by, created_at, retention_until) VALUES
('doc-terms', 'instance', 'ci-ubgx-eth', 'terms', 'UBGX Token Terms v4.2', 'dataroom://gold/terms-v4.pdf', '0xd5fb26c6e056a618ec20b07c3503da0aa44c14d97adbf8e631899dc88336d10f', '4.2', '2026-02-01', NULL, '0x25274113446fc9967ff356cc52345cfef6da98a040ae9fcfe006f246be79bfb4', 'confidential', 'p-daniel', '2026-01-28T10:00:00Z', '2033-01-28'),
('doc-prospectus', 'instance', 'ci-ubgx-eth', 'prospectus', 'UBGX Gold Token Prospectus', 'dataroom://gold/prospectus.pdf', '0xcd2c34921abde1fc9be66b51eb1aa03320940c32087aa56de472726fe870a040', '1.0', '2026-01-30', NULL, NULL, 'restricted', 'p-daniel', '2026-01-30T12:00:00Z', '2033-01-30'),
('doc-audit-cmtat', 'template', 'tpl-cmtat-300', 'security_audit', 'CMTAT 3.0.0 Security Audit', 'dataroom://audit/cmtat-3.0.0-halborn.pdf', '0x9fa3529efbdcfa922995d7ecd31dd806c73d8f679d3303dfbaf7d4deac9220b6', '3.0.0', '2024-09-15', '2026-12-15', NULL, 'internal', 'p-lucas', '2024-09-20T09:00:00Z', '2034-09-20'),
('doc-audit-rule', 'template', 'tpl-ruleengine-100', 'security_audit', 'CMTA RuleEngine Security Audit', 'dataroom://audit/ruleengine-chainsecurity.pdf', '0x668eaa53d9fa53af8e8f3a745f9627f4f7e118219978ba84b476a9c48cc6e006', '1.0', '2025-02-01', '2027-03-31', NULL, 'internal', 'p-lucas', '2025-02-10T09:00:00Z', '2035-02-10'),
('doc-audit-dvp', 'template', 'tpl-dvp-100', 'security_audit', 'CMTA DvP Security Audit', 'dataroom://audit/dvp-halborn.pdf', '0x313a23e0f774a0a76ad46d94fd9d874e4ff5313cde32a06493755d96409c12d9', '1.0', '2025-05-01', '2027-03-31', NULL, 'internal', 'p-lucas', '2025-05-20T09:00:00Z', '2035-05-20'),
('doc-por', 'instance', 'ci-ubgx-eth', 'proof_of_reserve', 'Gold Reserve Attestation October 2026', 'dataroom://gold/proof-of-reserve-2026-10.pdf', '0x9bbdbceb0fb06813c6f52ad29e203d87a337dc4317fd04d1a4908a3f6f7ea336', '2026-10', '2026-10-24', '2026-11-15', '0xfa924c68d5464593b5329b04e665b22bfed8e8bee6a6c532341ae98e14264537', 'confidential', 'p-elena', '2026-10-24T16:00:00Z', '2033-10-24'),
('doc-insurance', 'instance', 'ci-ubgx-eth', 'insurance', 'Gold Vault Insurance Certificate', 'dataroom://gold/insurance-2026.pdf', '0xc1be5a9b711cbc24e52f6e9dc6acb2db812647030da95c89f249a4ccb2f4e13e', '2026', '2026-07-01', '2027-06-30', NULL, 'confidential', 'p-elena', '2026-07-01T10:00:00Z', '2033-07-01'),
('doc-dora', 'instance', 'ci-ubgx-eth', 'dora_register_entry', 'DORA Register of Information Extract', 'dataroom://regulatory/dora-gold-2026.pdf', '0x1ae23ebe60f402e0ed9428ea69000063dcb5c8487edd07788f7a922e33c373d2', '2026-Q4', '2026-10-01', '2027-01-31', NULL, 'restricted', 'p-andrea', '2026-10-01T09:00:00Z', '2032-10-01'),
('doc-manifest', 'deployment_request', 'DR-2026-0042', 'deployment_manifest', 'UBGX Ledger Deployment Manifest', 'dataroom://deployments/dr-2026-0042-manifest.json', '0x00c7d6606ad9a740a4c96a4f82a122c1be3bd936ed33af8ca72444dcad82c2b0', '1.0', '2026-03-15', NULL, '0x212b490d6930d8c0947ff47cc4175a4fe2dd0913b7c11de41f10668564bd9c39', 'internal', 'p-priya', '2026-03-15T12:00:00Z', '2033-03-15'),
('doc-pentest', 'template', 'tpl-cmtat-300', 'penetration_test', 'Gold Platform Penetration Test 2026', 'dataroom://security/pentest-gold-2026.pdf', '0xd98f57cc362e128b2f51488e96dd39e498baba0b84cdd334090eab516f736bb6', '2026', '2026-09-01', '2027-09-01', NULL, 'internal', 'p-lucas', '2026-09-01T09:00:00Z', '2033-09-01'),
('doc-legal-lux', 'deployment_request', 'DR-2026-0051', 'legal_opinion', 'Luxembourg Token Legal Opinion', 'dataroom://legal/lux-token-opinion.pdf', '0xb1539bb19e97cccce236d5531f77e5145b80fa95070d66389cc91e1211ff2beb', '1.0', '2026-10-18', '2027-03-31', NULL, 'restricted', 'p-daniel', '2026-10-18T15:00:00Z', '2033-10-18'),
('doc-postmortem', 'change_request', 'CR-2026-013', 'postmortem', 'UAT Pause Post-mortem', 'dataroom://incidents/INC-2026-014-postmortem.pdf', '0x2b7aeba4082f9a58f2b1648e807194b97c567bf7152ccafc70e10e9acfa577d7', '1.0', '2026-10-21', NULL, NULL, 'internal', 'p-nina', '2026-10-21T10:00:00Z', '2033-10-21');

INSERT INTO attestation (id, instance_id, template_id, attestation_type, provider, result, score, report_uri, report_hash, issued_at, expires_at, status, onchain_attestation_uid, notes) VALUES
('att-cmtat-audit', NULL, 'tpl-cmtat-300', 'security_audit', 'Halborn', 'pass', '0 critical / 2 low', 'dataroom://audit/cmtat-3.0.0-halborn.pdf', '0x9fa3529efbdcfa922995d7ecd31dd806c73d8f679d3303dfbaf7d4deac9220b6', '2024-09-15', '2026-12-15', 'valid', NULL, 'Independent audit of CMTAT 3.0.0.'),
('att-cmtat-pentest', NULL, 'tpl-cmtat-300', 'penetration_test', 'Group Red Team', 'pass', 'No high findings', 'dataroom://security/pentest-gold-2026.pdf', '0xd98f57cc362e128b2f51488e96dd39e498baba0b84cdd334090eab516f736bb6', '2026-09-01', '2027-09-01', 'valid', NULL, 'Platform and key-management test.'),
('att-cmtat320-self', NULL, 'tpl-cmtat-320', 'self_assessment', 'Internal security review', 'conditional', 'Open findings', 'dataroom://audit/cmtat-3.2.0-self-assessment.pdf', '0xd07cca96547e064345cc59ef581e00cf9b9ab065db9dc0ed76c747be31fa0a05', '2026-08-15', '2026-10-01', 'expired', NULL, 'Not a substitute for an independent audit.'),
('att-ubgx-eth-bytes', 'ci-ubgx-eth', NULL, 'bytecode_match', 'Sourcify', 'exact match', 'Runtime code hash equal', 'https://sourcify.dev/#/lookup/0x919d4f9416a4cf4b2b966eb4ac354e740dc094c6', '0xbece8e0a9c1935e03bf705471f5f95a3d964602b15e9246d1164f2cca5a6228b', '2026-02-11', NULL, 'valid', NULL, 'Exact match against the approved template.'),
('att-ubgx-besu-bytes', 'ci-ubgx-besu', NULL, 'bytecode_match', 'Internal bytecode manifest', 'exact match', 'Runtime code hash equal', 'dataroom://deployments/dr-2026-0042-bytecode.json', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '2026-03-18', NULL, 'valid', NULL, 'Independent rebuild and manifest comparison.'),
('att-por-eth', 'ci-ubgx-eth', NULL, 'proof_of_reserve', 'Helvetia Assurance AG', 'pass', '101.0% coverage', 'dataroom://gold/proof-of-reserve-2026-10.pdf', '0x9bbdbceb0fb06813c6f52ad29e203d87a337dc4317fd04d1a4908a3f6f7ea336', '2026-10-24', '2026-11-15', 'valid', '0xfa924c68d5464593b5329b04e665b22bfed8e8bee6a6c532341ae98e14264537', 'Monthly attestation.'),
('att-por-besu', 'ci-ubgx-besu', NULL, 'proof_of_reserve', 'Helvetia Assurance AG', 'pass', '101.0% coverage', 'dataroom://gold/proof-of-reserve-2026-10.pdf', '0x9bbdbceb0fb06813c6f52ad29e203d87a337dc4317fd04d1a4908a3f6f7ea336', '2026-10-24', '2026-11-15', 'valid', '0xfa924c68d5464593b5329b04e665b22bfed8e8bee6a6c532341ae98e14264537', 'Same auditor report; separate bar allocation.'),
('att-insurance', 'ci-ubgx-eth', NULL, 'insurance', 'Swiss Insurance Partners AG', 'pass', 'CHF 250m limit', 'dataroom://gold/insurance-2026.pdf', '0xc1be5a9b711cbc24e52f6e9dc6acb2db812647030da95c89f249a4ccb2f4e13e', '2026-07-01', '2027-06-30', 'valid', NULL, 'Allocated vault cover.'),
('att-legal-eth', 'ci-ubgx-eth', NULL, 'legal_opinion', 'Zurich Legal Partners AG', 'pass', 'Enforceable security', 'dataroom://legal/ubgx-opinion.pdf', '0xb1539bb19e97cccce236d5531f77e5145b80fa95070d66389cc91e1211ff2beb', '2026-02-01', '2027-03-31', 'valid', NULL, 'Swiss law legal opinion.'),
('att-dora', 'ci-ubgx-eth', NULL, 'dora_register_entry', 'Group Operational Risk', 'pass', 'Entry complete', 'dataroom://regulatory/dora-gold-2026.pdf', '0x1ae23ebe60f402e0ed9428ea69000063dcb5c8487edd07788f7a922e33c373d2', '2026-10-01', '2027-01-31', 'valid', NULL, 'ICT third-party and outsourcing register entry.'),
('att-rule-audit', NULL, 'tpl-ruleengine-100', 'security_audit', 'ChainSecurity', 'pass', '0 critical / 1 medium', 'dataroom://audit/ruleengine-chainsecurity.pdf', '0x668eaa53d9fa53af8e8f3a745f9627f4f7e118219978ba84b476a9c48cc6e006', '2025-02-01', '2027-03-31', 'valid', NULL, NULL),
('att-dvp-audit', NULL, 'tpl-dvp-100', 'security_audit', 'Halborn', 'pass', '0 critical / 3 low', 'dataroom://audit/dvp-halborn.pdf', '0x313a23e0f774a0a76ad46d94fd9d874e4ff5313cde32a06493755d96409c12d9', '2025-05-01', '2027-03-31', 'valid', NULL, NULL),
('att-safe-audit', NULL, 'tpl-safe-140', 'security_audit', 'Ackee Blockchain', 'pass', '0 critical', 'dataroom://audit/safe-1.4.0-ackee.pdf', '0x521d4de9ad324eca0cbf2801b011511d2453dab25ce48a48c5f7d977bd213bc4', '2025-06-01', '2027-06-30', 'valid', NULL, NULL),
('att-ccip-audit', NULL, 'tpl-ccip-100', 'security_audit', 'Chainlink Labs', 'pass', 'Adapter only', 'dataroom://audit/ccip-adapter.pdf', '0x8c0f900218ba7c4022e44f2993df59d56d5b15887572f4d4aa3774072784d450', '2026-07-01', '2026-12-15', 'valid', NULL, 'Template remains draft; bridge approval is separate.'),
('att-por-contract', 'ci-proof-of-reserve', NULL, 'attestation_registry', 'Group Security', 'pass', 'Hash anchoring verified', 'dataroom://security/por-contract-review.pdf', '0x4cba7853cd13a00f640249b9049b37e263b93d578c61070d4db745a7cd5d44a8', '2026-03-18', '2027-05-31', 'valid', NULL, NULL);

INSERT INTO onchain_event (chain_id, instance_id, block_number, block_hash, tx_hash, log_index, event_name, signature, payload_json, observed_at) VALUES
('ch-eth-mainnet', 'ci-ubgx-eth', 21400005, '0x9e2a7c4d1f8b3a6e0c5d9b2f4a7c1e8d3b6f0a9c2e5d7b4f1a8c3e6d0b9f2a5c', '0xf9539180f98e22938d1b34176383a3f69de4331a1a23c34f132974d0d225f4c0', 0, 'Upgraded', 'Upgraded(address)', '{"implementation":"0xf70be54517e4f2c31a25be1432572c56b77024a3"}', '2026-02-11T08:06:00Z'),
('ch-eth-mainnet', 'ci-ubgx-eth', 21400006, NULL, '0x43cfbc9bef05b1e6d9e77ff82368ecc78f565d5e0c647aa26bf0b576fcdbba40', 0, 'AdminChanged', 'AdminChanged(address,address)', '{"previousAdmin":"0x0000000000000000000000000000000000000000","newAdmin":"0xf26274801325d20a15a830ce48cdae4f79fd907f"}', '2026-02-11T08:07:00Z'),
('ch-besu-prod', 'ci-ubgx-besu', 1841202, NULL, '0xa041e1ef3baad1b891259aca20a0eba20f5f0fea22544f43a136eb6650099895', 0, 'RoleGranted', 'RoleGranted(bytes32,address,address)', '{"role":"MINTER_ROLE","account":"0x21da7162938af12d11ddb53851ddd40e306c50fd","sender":"0xc3b5e332056d18c4febe491b0a27049887df48dd"}', '2026-03-18T10:43:00Z'),
('ch-besu-prod', 'ci-ubgx-besu', 1841202, NULL, '0xa041e1ef3baad1b891259aca20a0eba20f5f0fea22544f43a136eb6650099895', 1, 'Transfer', 'Transfer(address,address,uint256)', '{"from":"0x0000000000000000000000000000000000000000","to":"0x21da7162938af12d11ddb53851ddd40e306c50fd","value":"325000000"}', '2026-03-18T10:43:00Z'),
('ch-besu-prod', 'ci-ruleengine-gold', 1841205, NULL, '0xdaede5133d52eab55eecf2f9463fc6fef29ac284399f65a017a3dddeafd78f85', 0, 'RuleEngineChanged', 'RuleEngineChanged(address)', '{"ruleEngine":"0x7f0d1e772365a8ea8c4d292c9be57c9910dbab25"}', '2026-03-18T10:47:00Z'),
('ch-besu-prod', 'ci-proof-of-reserve', 1844300, NULL, '0xfa924c68d5464593b5329b04e665b22bfed8e8bee6a6c532341ae98e14264537', 0, 'ReserveAttested', 'ReserveAttested(bytes32,uint256,uint256)', '{"reportHash":"0x9bbdbceb0fb06813c6f52ad29e203d87a337dc4317fd04d1a4908a3f6f7ea336","coverageBps":10100,"asOf":"2026-10-24"}', '2026-10-24T16:00:00Z'),
('ch-besu-uat', 'ci-ubgx-besu-uat', 1200800, NULL, '0x323a97e6132105996582e749236014ceffd490802bcc5c3edec36db8c8311548', 0, 'Paused', 'Paused(address)', '{"account":"0xc3b5e332056d18c4febe491b0a27049887df48dd"}', '2026-10-20T14:12:00Z'),
('ch-besu-uat', 'ci-ubgx-besu-uat', 1200810, NULL, '0x2d878ecaa6a8a73fe61b6fbdfc8e6f7a1990e4c9009f5a340ae7871ccc80333a', 0, 'Unpaused', 'Unpaused(address)', '{"account":"0xc3b5e332056d18c4febe491b0a27049887df48dd"}', '2026-10-20T16:30:00Z'),
('ch-besu-prod', 'ci-rule-country', 1802000, NULL, '0x7c31f903d34914f3c83f5d81f44773ae3183c33f7e1449df221049c2a1d61f06', 0, 'OwnershipTransferred', 'OwnershipTransferred(address,address)', '{"previousOwner":"0xc3b5e332056d18c4febe491b0a27049887df48dd","newOwner":"0x8e21784f4a55d8cf2c21db7511499874ea54905e"}', '2026-10-18T09:40:00Z'),
('ch-besu-uat', 'ci-ubgx-lux-uat', 1201120, NULL, '0x26d9518425cfd2bbac15a81cd9b40027aa5d351b0ce71876ef609cc355a18b5e', 0, 'ContractDeployed', 'ContractDeployed(address,bytes32)', '{"instance":"0xb29eddb1d3f7b9949f46bbf16b766f6cc836046e","salt":"0x752b770c23b79c502edd10aace3740d0c5cd4a7e80e9bc044f150a2604cc13a2"}', '2026-10-22T08:31:00Z'),
('ch-eth-mainnet', 'ci-chainlink-xauusd', 21450000, NULL, '0x421c1376f0a935e4277f030d2ed8ba54f05b1ec7a8e0128881e7abb8735a5a70', 0, 'AnswerUpdated', 'AnswerUpdated(int256,uint256,uint256)', '{"current":"264850000000","roundId":"110680464442257400000","updatedAt":"2026-10-25T23:59:00Z"}', '2026-10-25T23:59:30Z');

UPDATE instance_role
SET source_event_id = (
    SELECT id FROM onchain_event
    WHERE tx_hash = '0x7c31f903d34914f3c83f5d81f44773ae3183c33f7e1449df221049c2a1d61f06'
    LIMIT 1
)
WHERE instance_id = 'ci-rule-country' AND role_name = 'OWNER';

INSERT INTO change_request (id, instance_id, change_type, description, status, risk_tier, requested_by, change_ticket, created_at, approved_at, implemented_at, implementation_tx, notes) VALUES
('CR-2026-004', 'ci-ubgx-eth', 'upgrade', 'Upgrade public UBGX implementation from 2.9.0 to CMTAT UUPS 3.0.0.', 'implemented', 'critical', 'p-priya', 'CHG-8610', '2026-01-20T10:00:00Z', '2026-02-05T16:30:00Z', '2026-02-11T08:06:00Z', '0xf9539180f98e22938d1b34176383a3f69de4331a1a23c34f132974d0d225f4c0', 'Storage-layout review and rollback rehearsal completed.'),
('CR-2026-011', 'ci-rule-maxholders', 'parameter', 'Increase max-holder threshold from 500 to 750 for the private-banking gold pool.', 'in_review', 'high', 'p-marco', 'CHG-9120', '2026-10-21T14:00:00Z', NULL, NULL, NULL, 'Requires Model Risk review because the rule changes investor eligibility capacity.'),
('CR-2026-013', 'ci-ubgx-besu-uat', 'pause', 'Emergency pause of the UAT gold token after a rule misconfiguration.', 'implemented', 'high', 'p-marco', 'CHG-9105', '2026-10-20T14:00:00Z', '2026-10-20T14:05:00Z', '2026-10-20T14:12:00Z', '0x323a97e6132105996582e749236014ceffd490802bcc5c3edec36db8c8311548', 'Post-mortem and corrective actions linked.');

INSERT INTO signoff (id, object_type, object_id, gate, required_role, decision, created_at)
SELECT
    'so-' || lower(cr.id) || '-' || lower(replace(p.gate, ' ', '-')),
    'change', cr.id, p.gate, p.required_role, 'pending', cr.created_at
FROM change_request cr
JOIN approval_policy p
  ON p.object_type = 'change'
 AND p.risk_tier = cr.risk_tier
WHERE cr.id IN ('CR-2026-004', 'CR-2026-011', 'CR-2026-013');

UPDATE signoff
SET decision = 'approved',
    decided_by = CASE required_role
        WHEN 'Business Owner' THEN 'p-elena'
        WHEN 'Compliance' THEN 'p-sophie'
        WHEN 'Legal' THEN 'p-daniel'
        WHEN 'Operational Risk' THEN 'p-andrea'
        WHEN 'Security' THEN 'p-lucas'
        WHEN 'Data Protection' THEN 'p-jonas'
        WHEN 'Model Risk' THEN 'p-sara'
        WHEN 'Platform Operations' THEN 'p-nina'
        WHEN 'Change Advisory Board' THEN 'p-reto'
    END,
    decided_at = '2026-02-05T16:30:00Z',
    comments = 'Upgrade approved after storage-layout and rollback review.',
    evidence_uri = 'evidence://cr-2026-004/' || lower(replace(gate, ' ', '-'))
WHERE object_type = 'change' AND object_id = 'CR-2026-004';

UPDATE signoff
SET decision = 'approved',
    decided_by = CASE required_role
        WHEN 'Business Owner' THEN 'p-elena'
        WHEN 'Compliance' THEN 'p-sophie'
        WHEN 'Operational Risk' THEN 'p-andrea'
        WHEN 'Security' THEN 'p-lucas'
        WHEN 'Platform Operations' THEN 'p-nina'
        WHEN 'Change Advisory Board' THEN 'p-reto'
    END,
    decided_at = '2026-10-20T14:05:00Z',
    comments = 'Emergency change approved; incident INC-2026-014 linked.',
    evidence_uri = 'evidence://cr-2026-013/' || lower(replace(gate, ' ', '-'))
WHERE object_type = 'change' AND object_id = 'CR-2026-013';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-elena', decided_at = '2026-10-21T15:00:00Z',
    comments = 'Business case for higher holder cap confirmed.',
    evidence_uri = 'evidence://cr-2026-011/business'
WHERE object_type = 'change' AND object_id = 'CR-2026-011' AND gate = 'BUSINESS';

UPDATE signoff
SET decision = 'approved', decided_by = 'p-sophie', decided_at = '2026-10-21T16:00:00Z',
    comments = 'No compliance objection; model-risk review remains open.',
    evidence_uri = 'evidence://cr-2026-011/compliance'
WHERE object_type = 'change' AND object_id = 'CR-2026-011' AND gate = 'COMPLIANCE';

INSERT INTO incident (id, instance_id, discovery_id, change_request_id, severity, status, title, summary, opened_at, contained_at, closed_at, playbook, postmortem_uri, regulatory_reportable) VALUES
('INC-2026-014', 'ci-ubgx-besu-uat', NULL, 'CR-2026-013', 'high', 'contained', 'UAT gold token paused after rule misconfiguration', 'A test-only rule change allowed a non-eligible holder to receive tokens. The token was paused, the rule was restored, and the environment was re-tested. No production or client impact.', '2026-10-20T14:00:00Z', '2026-10-20T16:30:00Z', NULL, 'SC-PLAYBOOK-03', 'dataroom://incidents/INC-2026-014-postmortem.pdf', 0),
('INC-2026-018', NULL, 'disc-001', NULL, 'medium', 'investigating', 'Unregistered contract discovered on the production ledger', 'Besu sync found a contract deployed by an address outside the approved deployer allowlist. No matching template hash. The contract is quarantined in the discovery queue and security is investigating.', '2026-10-25T06:05:00Z', NULL, NULL, 'SC-PLAYBOOK-07', NULL, 0),
('INC-2026-019', 'ci-rule-country', NULL, NULL, 'medium', 'investigating', 'Rule country admin transferred to an EOA', 'On-chain ownership of the country-restriction rule moved from the admin Safe to an EOA. The change was not linked to an approved change request. The rule remains active; remediation is to restore Safe ownership.', '2026-10-18T09:40:00Z', NULL, NULL, 'SC-PLAYBOOK-02', NULL, 0),
('INC-2026-006', NULL, NULL, NULL, 'low', 'closed', 'CMTAT 3.2 production release blocked by audit gate', 'The deployment request correctly failed the independent-audit gate. The release was stopped before any transaction was signed. Closed after the product team withdrew the request.', '2026-10-02T11:30:00Z', '2026-10-02T11:45:00Z', '2026-10-03T09:00:00Z', 'SC-PLAYBOOK-01', NULL, 0);

INSERT INTO control (id, code, name, framework, description, control_type, frequency, owner_org_unit_id) VALUES
('ctl-01', 'SC-01', 'Bytecode integrity', 'Internal Smart Contract Control Framework', 'Deployed runtime code must match an approved template hash, allowing for immutables and clone-normalised addresses.', 'preventive', 'per deployment', 'org-cio-sec'),
('ctl-02', 'SC-02', 'Source verification', 'Internal Smart Contract Control Framework', 'Source must be reproducibly verified against the deployed bytecode.', 'preventive', 'per deployment', 'org-cio-sec'),
('ctl-03', 'SC-03', 'Independent assurance', 'DORA / Internal', 'A valid independent audit or assessment must cover the template and its material dependencies.', 'preventive', 'monthly', 'org-cro-op'),
('ctl-04', 'SC-04', 'Deployment approvals', 'Internal / SOX', 'All blocking business, compliance, legal, risk, security, operations and CAB gates must be approved before deployment.', 'preventive', 'per deployment', 'org-cro-op'),
('ctl-05', 'SC-05', 'Privileged role custody', 'DORA / Internal', 'Admin, upgrade, mint and pause roles must be held by a Safe, timelock or HSM-backed service, not a personal EOA.', 'preventive', 'daily', 'org-cio-sec'),
('ctl-06', 'SC-06', 'On-chain monitoring', 'DORA', 'Deployments, role changes, upgrades, pauses and material transfers are monitored and alerted.', 'detective', 'continuous', 'org-cio-plt'),
('ctl-07', 'SC-07', 'Reserve attestation', 'MiCA / Internal', 'Token supply must be covered by a current, independently attested reserve snapshot.', 'detective', 'monthly', 'org-gwm-com'),
('ctl-08', 'SC-08', 'Change control', 'Internal / SOX', 'Material upgrades, parameter changes and role changes must be linked to an approved change request.', 'detective', 'continuous', 'org-cro-op'),
('ctl-09', 'SC-09', 'DORA register', 'DORA', 'In-scope contracts and ICT third-party arrangements are reflected in the DORA register of information.', 'preventive', 'quarterly', 'org-cro-op'),
('ctl-10', 'SC-10', 'Data protection', 'GDPR / Internal', 'No personal data is written on-chain; privacy groups and off-chain references are reviewed before deployment.', 'preventive', 'per deployment', 'org-legal');

INSERT INTO instance_control (instance_id, control_id, status, evidence_uri, last_tested_at, next_test_due, notes)
SELECT
    ci.id,
    c.id,
    CASE
        WHEN c.code = 'SC-01' AND ci.verification_status IN ('exact', 'match') THEN 'pass'
        WHEN c.code = 'SC-01' THEN 'fail'
        WHEN c.code = 'SC-02' AND ci.verification_status IN ('exact', 'match') THEN 'pass'
        WHEN c.code = 'SC-02' THEN 'fail'
        WHEN c.code = 'SC-03' AND ci.id = 'ci-ubgx-besu-v2' THEN 'not_applicable'
        WHEN c.code = 'SC-03' AND t.audit_status IN ('external', 'internal') AND date(t.audit_valid_until) >= date('2026-10-26') THEN 'pass'
        WHEN c.code = 'SC-03' THEN 'fail'
        WHEN c.code = 'SC-04' AND ci.id = 'ci-dvp-gold' THEN 'exception'
        WHEN c.code = 'SC-04' AND ci.id IN ('ci-ubgx-besu-uat', 'ci-ubgx-lux-uat') THEN 'pass'
        WHEN c.code = 'SC-04' AND ci.deployment_request_id IS NULL THEN 'not_applicable'
        WHEN c.code = 'SC-04' AND (SELECT status FROM deployment_request WHERE id = ci.deployment_request_id) IN ('approved', 'deployed') THEN 'pass'
        WHEN c.code = 'SC-04' THEN 'fail'
        WHEN c.code = 'SC-05' AND ci.id = 'ci-rule-country' THEN 'fail'
        WHEN c.code = 'SC-05' AND ci.admin_address IS NULL THEN 'pass'
        WHEN c.code = 'SC-05' AND ci.admin_address IN (SELECT address FROM contract_instance WHERE template_id IN ('tpl-safe-140', 'tpl-timelock-100')) THEN 'pass'
        WHEN c.code = 'SC-05' THEN 'exception'
        WHEN c.code = 'SC-06' AND ci.status IN ('active', 'deployed', 'paused') THEN 'pass'
        WHEN c.code = 'SC-06' THEN 'not_applicable'
        WHEN c.code = 'SC-07' AND t.id NOT IN ('tpl-cmtat-300', 'tpl-cmtat-230', 'tpl-cmtat-uups-300') THEN 'not_applicable'
        WHEN c.code = 'SC-07' AND ci.id IN ('ci-ubgx-besu-uat', 'ci-ubgx-lux-uat', 'ci-ubgx-besu-v2') THEN 'not_applicable'
        WHEN c.code = 'SC-07' AND EXISTS (SELECT 1 FROM v_token_reserve r WHERE r.instance_id = ci.id AND r.reserve_state = 'current') THEN 'pass'
        WHEN c.code = 'SC-07' THEN 'fail'
        WHEN c.code = 'SC-08' AND ci.id IN ('ci-dvp-gold', 'ci-rule-country') THEN 'exception'
        WHEN c.code = 'SC-08' THEN 'pass'
        WHEN c.code = 'SC-09' AND ci.id IN ('ci-ubgx-besu-uat', 'ci-ubgx-lux-uat', 'ci-ubgx-besu-v2') THEN 'not_applicable'
        WHEN c.code = 'SC-09' THEN 'pass'
        WHEN c.code = 'SC-10' THEN 'pass'
    END,
    'evidence://controls/' || ci.id || '/' || c.code,
    '2026-10-25',
    '2027-01-25',
    NULL
FROM contract_instance ci
JOIN template t ON t.id = ci.template_id
CROSS JOIN control c
WHERE ci.instance_kind = 'logical';

UPDATE instance_control
SET notes = 'Admin is an EOA. Remediation: transfer ownership to the 3-of-5 Safe and rotate keys.',
    exception_approved_by = 'p-andrea'
WHERE instance_id = 'ci-rule-country' AND control_id IN ('ctl-05', 'ctl-08');

UPDATE instance_control
SET notes = 'Backfilled deployment with incomplete original CAB evidence. Accepted temporarily; evidence remediation tracked.',
    exception_approved_by = 'p-andrea'
WHERE instance_id = 'ci-dvp-gold' AND control_id IN ('ctl-04', 'ctl-08');

INSERT INTO sync_run (id, chain_id, mode, from_block, to_block, blocks_scanned, txs_scanned, contracts_found, contracts_matched, unknown, errors, status, started_at, finished_at, checkpoint_block, error_text) VALUES
('sr-001', 'ch-besu-prod', 'incremental', 1844300, 1844400, 101, 1204, 2, 1, 1, 0, 'success', '2026-10-26T06:00:00Z', '2026-10-26T06:00:42Z', 1844400, NULL),
('sr-002', 'ch-eth-mainnet', 'incremental', 21490000, 21490100, 101, 1850, 1, 0, 1, 0, 'success', '2026-10-26T06:05:00Z', '2026-10-26T06:06:10Z', 21490100, NULL),
('sr-003', 'ch-besu-uat', 'incremental', 1201120, 1201200, 81, 310, 1, 1, 0, 0, 'success', '2026-10-25T22:00:00Z', '2026-10-25T22:00:18Z', 1201200, NULL),
('sr-004', 'ch-besu-prod', 'backfill', 1800000, 1844300, 44301, 512000, 14, 12, 2, 3, 'partial', '2026-10-24T02:00:00Z', '2026-10-24T02:19:00Z', 1844300, '3 receipt timeouts retried in the next run'),
('sr-005', 'ch-eth-mainnet', 'backfill', 21000000, 21490000, 490001, 6100000, 42, 40, 2, 1, 'partial', '2026-10-23T02:00:00Z', '2026-10-23T03:02:00Z', 21490000, 'RPC rate limit; checkpoint reached with one retry pending');

INSERT INTO discovery_queue (id, chain_id, address, runtime_code_hash, tx_hash, deployer_address, block_number, first_seen_at, status, suspected_template_id, classification, risk_hint, notes, resolved_by, resolved_at, linked_instance_id) VALUES
('disc-001', 'ch-besu-prod', '0x9b28f207057602afd2b7808e212c42daeb9eabd4', '0x9b28f207057602afd2b7808e212c42daeb9eabd450d9ec314d608fd7134071a4', '0xed9a8fbe915bf62350425f99599d118ae671d266a66ad6d354a851b8bd47fcff', '0x8e21784f4a55d8cf2c21db7511499874ea54905e', 1844395, '2026-10-26T06:00:30Z', 'triage', NULL, 'ERC-20-like selectors; no approved template hash', 'high', 'Deployer is not in the approved deployer allowlist. No matching template or factory event. Security and legal notified.', NULL, NULL, NULL),
('disc-002', 'ch-besu-prod', '0xb13d05c104d4480e0a5cc604d89c089609ba69f5', '0xb13d05c104d4480e0a5cc604d89c089609ba69f5d79b929967ac91e59d831616', '0xa729cb5dfa1681c10b87db8cf56d4173465cb63468e1e5d4a596209b01d608d8', '0x8e21784f4a55d8cf2c21db7511499874ea54905e', 1844399, '2026-10-26T06:00:31Z', 'new', NULL, 'Unknown contract; possibly a clone factory child', 'medium', 'Same deployer as disc-001. Awaiting triage.', NULL, NULL, NULL),
('disc-003', 'ch-eth-mainnet', '0xe58bc9e9181440f4929cd3542c6dd5be6afe3042', '0xe58bc9e9181440f4929cd3542c6dd5be6afe3042453f81e912c5fd350aa3dfd0', '0x1694c8104f0a3062ee1aea8f037543136d7fe2a4a048c4cf8692f00a76fa0e2c', '0x56fe73d267239acb9ddd9a850c484b414bd30477', 21490088, '2026-10-26T06:05:30Z', 'quarantined', 'tpl-cmtat-300', '94% bytecode similarity to CMTAT 3.0.0; metadata differs, source unverified', 'critical', 'Potential unauthorised clone of the gold token. Contract interactions blocked in the transaction-monitoring policy.', NULL, NULL, NULL),
('disc-004', 'ch-besu-prod', '0x010a7c53e35a55ec507a00ebbe0fa98283c3c5a2', '0x0d0b8b1533341356e019c71c314b6124a35a959dac86f39280c2e19753540f30', '0xd91731e8d44aeae6c57fc35326aa364cdcbfd917412b2d9a2fdb8be8a4feb0f8', '0xc3b5e332056d18c4febe491b0a27049887df48dd', 1750010, '2026-10-24T02:04:00Z', 'linked', 'tpl-multicall-300', 'Known low-risk shared utility', 'low', 'Matched the approved Multicall3 template and linked to the registered instance.', 'p-nina', '2026-10-24T08:00:00Z', 'ci-multicall-besu'),
('disc-005', 'ch-besu-uat', '0xb29eddb1d3f7b9949f46bbf16b766f6cc836046e', '0x53fac3fcedf987b84d7f3d34e3249ee3359aab68f11813b5ccd5d8da2a2a12c1', '0x26d9518425cfd2bbac15a81cd9b40027aa5d351b0ce71876ef609cc355a18b5e', '0xd8c048a9d8ae7cd05b98b93a0214c8f792167439', 1201120, '2026-10-25T22:00:05Z', 'linked', 'tpl-cmtat-300', 'Factory clone linked to the Luxembourg UAT instance', 'medium', 'Matched the approved CMTAT template and the factory event.', 'p-nina', '2026-10-25T22:05:00Z', 'ci-ubgx-lux-uat');

INSERT INTO audit_log (actor, actor_type, action, object_type, object_id, before_json, after_json, at, correlation_id, source_ip) VALUES
('priya.nair@example.com', 'person', 'deployment_request.created', 'deployment_request', 'DR-2026-0051', NULL, '{"template":"tpl-cmtat-300","chain":"ch-besu-prod","risk_tier":"high"}', '2026-10-19T08:15:00Z', 'corr-8f21', '10.20.4.18'),
('luca.bernardi@example.com', 'person', 'signoff.approved', 'signoff', 'so-dr-2026-0051-business', '{"decision":"pending"}', '{"decision":"approved","role":"Business Owner"}', '2026-10-20T09:30:00Z', 'corr-8f21', '10.20.6.44'),
('amelie.dubois@example.com', 'person', 'signoff.approved', 'signoff', 'so-dr-2026-0051-compliance', '{"decision":"pending"}', '{"decision":"approved","role":"Compliance"}', '2026-10-21T08:15:00Z', 'corr-8f21', '10.20.6.51'),
('service:besu-sync', 'service', 'discovery.found', 'discovery_queue', 'disc-001', NULL, '{"address":"0x9b28f207057602afd2b7808e212c42daeb9eabd4","reason":"no template hash"}', '2026-10-26T06:00:30Z', 'corr-sync-1844400', '10.30.2.9'),
('nina.baumann@example.com', 'person', 'discovery.linked', 'discovery_queue', 'disc-004', '{"status":"new"}', '{"status":"linked","instance":"ci-multicall-besu"}', '2026-10-24T08:00:00Z', 'corr-disc-004', '10.20.4.22'),
('andrea.vogel@example.com', 'person', 'control.exception.accepted', 'instance_control', 'ci-dvp-gold/ctl-04', '{"status":"fail"}', '{"status":"exception","reason":"backfill evidence gap"}', '2026-10-24T10:00:00Z', 'corr-ctl-dvp', '10.20.5.12'),
('system:policy-engine', 'system', 'deployment.blocked', 'deployment_request', 'DR-2026-0060', NULL, '{"reason":"template not approved; audit expired","template":"tpl-cmtat-320"}', '2026-10-02T11:30:00Z', 'corr-policy-0060', NULL),
('lucas.frei@example.com', 'person', 'template.reviewed', 'template', 'tpl-cmtat-320', '{"status":"draft"}', '{"status":"draft","finding":"independent audit missing"}', '2026-08-20T10:05:00Z', 'corr-tpl-320', '10.20.7.8');

