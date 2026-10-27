# Smart Contract Registry — Blueprint, Research & Gaps

**Version:** 0.1 · October 2026  
**Scope:** EVM-only for the first release (Besu permissioned + public Ethereum-compatible chains), with a path to non-EVM later.  
**Audience:** Software inventory / CMDB product team, digital-assets platform, CISO, operational risk, compliance, internal audit.

---

## 1. Executive summary

The bank does not just need an inventory of smart contracts. It needs a **controlled registry of approved code artifacts, every on-chain deployment, the business sign-off that authorised it, and the evidence that it still behaves as approved**.

The important distinction is:

> **A template is not a deployment. A deployment is not a product. A proxy is not an implementation. A mirrored token is not a second reserve claim.**

The demo therefore models four layers:

1. **Template** — the approved code artifact and its assurance package.
2. **Deployment request** — the business intent, chain, parameters, risk tier and approvals.
3. **Contract instance** — the actual on-chain address, including proxy, implementation and supporting-contract relationships.
4. **Product / service** — the commercial offering, legal entity, jurisdiction and reserve pool.

The registry is a **control plane**, not an explorer and not a wiki. It must be fed by three sources:

- the **deployment pipeline** (signed manifest, HSM-backed deployer, CI/CD identity);
- the **chain** (runtime code, receipts, proxy slots, events) via a Besu/EVM sync worker;
- the **business workflow** (risk-tiered sign-offs, evidence, exceptions, incidents).

A registry alone cannot stop a compromised key from deploying code. **Enforcement** comes from Besu account permissioning, HSM signing policy, CI/CD OIDC, factory allowlists, Safe/Timelock admin control and least-privilege role custody. The registry detects drift and creates accountability when enforcement fails.

---

## 2. Research: what open-source registries and adjacent tools exist?

No single open-source project covers template catalogue + deployment linkage + business sign-off + evidence + CMDB integration. The practical answer is to **compose** the registry of record with specialist tools.

| Project | What it is | What it gives you | What it does not give you | How to use it |
|---|---|---|---|---|
| **Sourcify** | Open-source, decentralised contract verification repository | Source/metadata verification, exact/match verification, IPFS, self-hostable API, multi-chain dataset | Business ownership, sign-offs, template lifecycle, CMDB, DORA evidence | Verification provider. Store the Sourcify match result and URL on the deployment; self-host for private chains. |
| **Blockscout** | Open-source block explorer | Verified-contract UI/API, proxy detection, token inventory, self-hosting, private-chain support | Governance, risk tiering, approval workflow, reserve reconciliation | Discovery and verification UI for Besu/private networks; do not rebuild an explorer. |
| **EBSI Trusted Contracts Registry** | EU public-sector on-chain registry of deployed contract metadata and templates | Close reference model: templates, contract metadata, factory/beacon-proxy deployment, authorised issuers | Bank-specific roles, legal entities, risk tiers, sign-offs, DORA, public/private reserve logic | Reuse the **template + deployment + factory** pattern; do not depend on EBSI governance. |
| **Hyperledger FireFly** | Apache-2.0 enterprise Web3 supernode | Contract manager, FireFly Interface (FFI) format, API generation, event listeners, Besu support, token connectors | Registry of record for business ownership and approvals; bank-grade GRC | Use as runtime integration layer: contract ABI/FFI, event subscription, API generation. |
| **EthPM** | Ethereum package management specification | Package/version manifest idea for contract artifacts | Active ecosystem, deployment linkage, governance, bank controls | Inspiration for template packaging; not a dependency. |
| **Ethereum Attestation Service (EAS)** | Open attestation protocol | On-chain attestations, schemas, revocation, composability | Business workflow, role model, evidence retention, privacy | Anchor **hashes** of sign-off bundles / reserve attestations on a permissioned chain or EAS; keep documents off-chain. |
| **ONCHAINID / ERC-3643** | On-chain identity and permissioned security-token suite | Wallet-to-identity registry, trusted issuers, claim topics, compliance hooks | Deployment/template registry; business approvals | Use as **identity/compliance contracts** linked from the token instance. |
| **CMTAT + CMTA RuleEngine** | Open-source security-token framework and external rule engine | ERC-20 + ERC-3643/1404-style restrictions, rule engine, audit trail, UUPS variant, tokenized-gold precedent | Registry, sign-offs, key custody, reserve accounting | Use as the token template family and rule-engine pattern; track version and audit scope carefully. |
| **Safe Transaction Service** | Open-source multisig transaction service | Proposals, confirmations, execution queue, API | Business sign-off policy, risk tiering, evidence | Use as **execution evidence** for admin/upgrade actions; link Safe tx hashes to registry change requests. |
| **OpenZeppelin Upgrades** | Upgrade safety tooling | Storage-layout checks, proxy patterns, upgrade validation | Registry, approvals, runtime monitoring | Use in CI for proxy upgrades; store the validation report as evidence. |
| **4byte directory** | Function-selector registry | Selector lookup for unknown bytecode | Deployment identity, source verification | Triage aid for unknown contracts; not authoritative. |
| **Baseline Protocol** | OASIS standard/pattern for private business processes on public chains | Registry/anchor patterns, zero-knowledge workflow ideas | Full bank registry product | Architectural reference for document-hash anchoring and privacy. |

### Research conclusion

Build the **registry of record** yourself, because the bank-specific value is in the data model and workflow: legal entity, division, business owner, risk tier, sign-off matrix, reserve pool, exception, incident and DORA mapping. Integrate:

- **Sourcify/Blockscout** for verification and discovery UI;
- **Besu JSON-RPC** for authoritative on-chain evidence;
- **FireFly** (optional) for runtime contract APIs and event subscriptions;
- **EAS / on-chain anchoring** for tamper-evident evidence bundles;
- **Safe/Timelock** for execution evidence;
- **ServiceNow/CMDB, GRC and SIEM** for enterprise context;
- **CMTAT/RuleEngine/ERC-3643** as domain templates, not as the registry.

---

## 3. Reference architecture

```
          ServiceNow CMDB        GRC / Archer          IdP / Azure AD        SIEM / Splunk
                  \                   |                     |                    /
                   +------------- Registry API & workflow --------------------+
                   |  templates | deployment requests | contract instances    |
                   |  sign-offs | evidence | attestations | incidents | links  |
                   +------------- PostgreSQL + object store + WORM audit -----+
                        ^                    ^                       ^
                        |                    |                       |
             Besu / EVM sync worker     Deployment pipeline      Sourcify / Blockscout
             (JSON-RPC, events,         (signed manifest,        (source verification,
              proxy slots, privacy)      HSM, CI/CD OIDC)         proxy detection)
                        |                    |
             Besu permissioned / Ethereum mainnet / L2s / future Canton
```

### 3.1 Source-of-truth hierarchy

| Question | Authoritative source |
|---|---|
| What code is approved? | Registry template + audit/attestation package |
| What is actually on-chain? | Chain state via JSON-RPC (code hash, slots, events) |
| Who owns the business product? | Registry (business owner, org unit, legal entity) |
| Who approved deployment? | Registry sign-off bundle + IdP identity + evidence hashes |
| Is the source verified? | Sourcify / Blockscout / reproducible build |
| Is it still operating as approved? | Monitoring/SIEM + registry control tests + incidents |
| What is the CMDB CI? | ServiceNow/CMDB; registry links to it |
| What is the DORA register entry? | GRC/DORA register; registry supplies evidence and links |

The chain is **evidence**, not the system of record. The CMDB is **software inventory**, not the contract registry. The GRC tool is **risk/controls**, not the deployment inventory. The registry is the join key.

---

## 4. Data model

### 4.1 Four layers, not one table

| Layer | Example | Key fields | Why separate |
|---|---|---|---|
| **Template** | CMTAT 3.0.0, RuleEngine 1.0.0, ERC-1967 proxy | `template_key`, `version`, `runtime_code_hash`, `initcode_hash`, compiler, audit, owner, status | Reuse one approval and one audit across many deployments. |
| **Deployment request** | “Deploy UBGX Luxembourg on Besu prod” | chain, environment, product, legal entity, jurisdiction, risk tier, config hash, manifest hash, target window | Captures intent and approvals before an address exists. |
| **Contract instance** | `0x4600…411e` on Besu prod | address, template, kind, representation, proxy type, implementation, admin, deployer, block, tx, verification | Captures the actual on-chain object. |
| **Product / service** | “UBGX Gold Token (Ledger)” | business owner, division, legal entity, reserve pool, classification, criticality | A product can have multiple instances (public, ledger, mirror, wrapped) without becoming multiple products. |

### 4.2 Instance kinds and representations

| Field | Values | Rule |
|---|---|---|
| `instance_kind` | `logical`, `implementation`, `supporting` | Only `logical` counts as a product deployment. Implementations and shared infrastructure are linked, not counted. |
| `representation` | `native`, `mirror`, `wrapped`, `receipt`, `not_applicable` | Prevents double-counting supply and reserve. |
| `proxy_type` | `none`, `eip1967-transparent`, `eip1967-uups`, `beacon`, `eip1167-clone`, `diamond`, `custom` | Proxy shell and implementation are separate records or linked fields. |
| `status` | `proposed`, `deployed`, `active`, `paused`, `deprecated`, `retired`, `quarantined` | Lifecycle, not just “exists”. |

### 4.3 Template fields that are usually missing

- `template_key` + semantic version, not just a filename.
- `source_repo`, `source_path`, `git_commit`, `compiler_version`, `evm_version`, `license`.
- `initcode_hash`, `runtime_code_hash`, `abi_hash` (canonical JSON), dependency versions.
- `audit_status` (`none`, `self`, `internal`, `external`), provider, scope, `audit_valid_until`.
- `ethtrust_level` (EEA EthTrust [S]/[M]/[Q]) where applicable.
- `default_risk_tier`, `owner_org_unit_id`, `status`, `approved_at`, `retired_at`.
- Template dependencies (`inherits`, `uses`, `requires`, `compatible_with`).
- Software CI link (`template_ci`) to ServiceNow/CMDB.
- Parameter schema: name, type, required, default, sensitive, constraints.
- SBOM and compiler provenance (not shown in the demo, but should be in production).

### 4.4 Deployment instance fields that are usually missing

- `deployer_address` and **deployer identity** (HSM service account, CI/CD workload identity, contractor — not just an address).
- `salt`, `init_code_hash`, `manifest_hash`, `config_hash`, `deployment_request_id`.
- `privacy_group` for Besu private state.
- `is_canonical`, `supersedes_id`, representation.
- `verification_status` (`exact`, `match`, `partial`, `unverified`, `failed`) and provider.
- `admin_address` + `admin_controlled_by` link to Safe/Timelock.
- `business_owner_id`, `org_unit_id`, `legal_entity`, `jurisdiction`, `classification`, `risk_tier`, `criticality`.
- Token metadata and reserve pool (separate table), not free-text in a spreadsheet.

---

## 5. Contract taxonomy — what else should be in the registry?

The user’s categories (rule engine, utility, value) are a good start but too coarse for a bank. The registry should classify by **risk and lifecycle role**, not just by technical pattern.

| Category | Examples | Why the registry needs it | Extra controls |
|---|---|---|---|
| **Security / regulated token** | CMTAT, ERC-3643, ERC-1400, ERC-20 with restrictions | Carries investor rights, transfer restrictions, reserve claims | Legal opinion, prospectus/terms, audit, reserve, compliance rule set |
| **Tokenized value** | ERC-4626 vault, tokenized deposit, money-market fund, warehouse receipt, NFT receipt | Holds or represents value | Custody, NAV, insolvency remoteness, redemption |
| **Compliance / rule engine** | CMTA RuleEngine, rules (max holders, country, sanctions, lock-up, allowlist), compliance modules | Changes who can transact; can freeze/deny clients | Model risk, parameter change control, compliance sign-off, rule versioning |
| **Identity** | ERC-3643 IdentityRegistry, TrustedIssuersRegistry, ClaimTopicsRegistry, ONCHAINID | Maps wallets to eligible investors | PII off-chain, claim issuer trust, GDPR, revocation |
| **Settlement / value transfer** | DvP, escrow, payment splitter, collateral vault, redemption queue | Moves value or locks collateral | Settlement finality, failure handling, legal enforceability, reconciliation |
| **Proxy / upgrade** | Transparent, UUPS, beacon, diamond | Changes code behind a stable address | Storage layout, timelock, upgrade delay, implementation hash |
| **Factory / deployment** | CREATE2 factory, clone factory, deterministic deployer | Creates other contracts; can bypass per-deployment review | Factory allowlist, salt policy, child registration, event monitoring |
| **Governance / account** | Safe, TimelockController, access-control roles, ERC-4337 smart account, paymaster, session keys | Controls privileged actions and keys | Quorum, signer policy, key custody, recovery, AA paymaster risk |
| **Oracle / data** | Chainlink price feed, proof-of-reserve registry, NAV oracle, attestation registry | Bad data can misprice or block transfers | Provider concentration, heartbeat, deviation, staleness, fallback |
| **Security / lifecycle** | Pause guardian, circuit breaker, rate limiter, recovery, migration | Incident response and safe shutdown | Playbooks, authority, test cadence, break-glass |
| **Utility** | Multicall, Permit2, signature verifier, batcher, deterministic deployer | Low risk individually, high dependency concentration | Version pinning, canonical address, no privileged roles |
| **Interop / bridge** | CCIP adapter, LayerZero OFT adapter, wrapped representation | Introduces cross-chain supply, finality and counterparty risk | Bridge assessment, canonical mapping, supply reconciliation, pause |
| **Privacy** | ZK verifier, FHE contract, private settlement | Hides data but adds trust setup and verifier-key risk | Trusted setup, verifier-key governance, regulator access |
| **Document / attestation** | Document registry, EAS schema, proof-of-reserve anchor | Anchors legal/audit evidence | Hash correctness, retention, revocation |
| **Non-EVM adapter** | Canton, Solana, Tezos CMTAT | Future scope | Separate adapter model; do not pretend EVM semantics apply |

### 5.1 The “value smart contract” ambiguity

“Value smart contract” should be split into at least three things:

1. **Value-bearing token** — the token itself (CMTAT, deposit token, vault share).
2. **Value-holding contract** — escrow, collateral vault, DvP settlement.
3. **Value-moving utility** — payment splitter, batch payer, redemption queue.

They have different owners, controls and reserve/accounting treatment. A single `value` category will hide material risk.

### 5.2 Missing contract types in the current demo

The demo covers the core patterns but a production taxonomy should add:

- **Tokenized fund / ERC-4626 vault** with NAV oracle and subscription/redemption queue.
- **Collateral vault / lending** with LTV, liquidation, oracle and legal pledge.
- **Cross-chain adapter** (CCIP/LayerZero) and wrapped representation.
- **Account abstraction** (ERC-4337 smart account, paymaster, session keys) if the operating model uses it.
- **ZK / privacy verifier** for private eligibility or settlement.
- **Document/attestation registry** for terms, proof of reserve and audit anchors.
- **Recovery / migration contract** for key loss and product migration.
- **Sanctions / travel-rule adapter** if on-chain screening is used.
- **Rate limiter / circuit breaker** for incident containment.
- **NFT warehouse receipt / bar-level representation** if individual bars are tokenized.
- **Non-EVM adapter** for Canton/Solana/Tezos, separate from the EVM registry.

The demo already includes a **draft** CCIP adapter, ERC-4337 account and Groth16 verifier to show how the catalogue handles future/unapproved types without deploying them. It also includes DvP, escrow, collateral-vault template, CHF deposit token, Safe, timelock, oracle, proof-of-reserve and identity contracts.

---

## 6. Linking templates to on-chain deployments

This is the hard part. The registry must answer: **which on-chain address came from which approved template, with which parameters and which approval?**

### 6.1 Match signals (strongest to weakest)

| Signal | Use | Caveat |
|---|---|---|
| `runtime_code_hash` exact | Strongest match for immutable contracts | Constructor immutables can change runtime code; proxy shell differs from implementation. |
| `initcode_hash` + salt | Strong for factory/CREATE2 deployments | Need the exact creation input and compiler settings. |
| Proxy implementation hash | Strong for UUPS/transparent/beacon | Must read EIP-1967 slots and follow upgrades. |
| EIP-1167 clone normalisation | Strong for minimal proxies | Zero out the embedded implementation address before hashing. |
| Factory event + salt | Strong if factory is trusted | Factory can deploy arbitrary code if compromised. |
| ABI/selectors only | Weak triage | Many contracts share ERC-20 selectors. Never auto-approve on selectors. |
| Deployer allowlist | Control signal, not identity | Deployer key can be compromised. |

### 6.2 Proxy and upgrade tracking

- Store the **logical** instance at the proxy address and link `delegates_to` the implementation instance.
- Read EIP-1967 implementation slot: `0x3608…bbc`; admin slot: `0xb531…6103`; beacon slot: `0xa3f0…3d50`.
- For beacon proxies, call `implementation()` on the beacon.
- Index `Upgraded(address)`, `BeaconUpgraded(address)`, `AdminChanged(address,address)`.
- Every upgrade must be a `change_request` linked to a new implementation hash, storage-layout review, timelock execution and post-implementation verification.
- Do **not** treat an implementation contract as a separate product; it is `instance_kind = implementation`.

### 6.3 Deterministic deployments

- Store `salt`, `init_code_hash`, `factory_instance_id` and `deployment_tx`.
- Verify the predicted address independently (`CREATE2` formula) and compare with `receipt.contractAddress`.
- Record whether the address is canonical for the product or a test/canary clone.
- If a factory is used, monitor the factory’s `ContractDeployed` events and link children automatically to **triage**, not to production.

### 6.4 Configuration drift

The template has a parameter schema. The instance has captured constructor/initializer/admin values. The registry should flag:

- `maxSupply` above the approved product limit;
- `ruleEngine` address not the approved rule engine;
- `admin` not a Safe/Timelock;
- oracle feed different from the approved feed;
- missing/extra rule modules;
- reserve pool mismatch.

This is more valuable than storing a PDF of the deployment script.

---

## 7. Besu integration

### 7.1 Read path

| Need | Besu JSON-RPC | Notes |
|---|---|---|
| Chain identity | `eth_chainId`, `net_version` | Reject mismatches. |
| Latest block | `eth_blockNumber` | Checkpoint every run. |
| Block + txs | `eth_getBlockByNumber(hex, true)` | Use full tx to find creations. |
| Receipt | `eth_getTransactionReceipt` | `contractAddress`, status, logs. |
| Code | `eth_getCode` | Runtime code; hash it. |
| Proxy slots | `eth_getStorageAt` | EIP-1967 implementation/admin/beacon. |
| Beacon implementation | `eth_call` `implementation()` | Selector `0x5c60da1b`. |
| Events | `eth_getLogs` / `eth_subscribe` | Upgraded, AdminChanged, RoleGranted, Paused, custom. |
| Trace (optional) | `debug_traceTransaction` / `trace_*` | Internal calls and factory children; expensive. |
| Private tx | `priv_getTransactionReceipt` and privacy-group APIs | Validate on your Besu version; track privacy group ID. |

### 7.2 Private Besu specifics

- Put RPC behind mTLS/OIDC; never expose `8545`.
- Use a read-only service account with minimal API namespaces (`eth`, `net`, `web3`; `priv` only if required).
- Track the **privacy group** for private deployments and private state. A private contract may not be visible to a node outside the group.
- Store both the private transaction hash and the on-chain marker transaction hash if using private transactions.
- Account permissioning/allowlisting is the real deployment control; the registry is detective, not preventive.
- Finality: QBFT/IBFT finality is fast but still use a confirmation buffer for reorg-safe ingestion; store block hash and re-check on reorgs.
- Besu plugins/events can provide richer hooks, but JSON-RPC is the lowest-common-denominator and works for public and private networks.

### 7.3 Sync worker design

1. `eth_chainId` check.
2. Read checkpoint from `sync_run.checkpoint_block`.
3. Fetch blocks in batches; for each creation tx:
   - receipt status 0x1;
   - `contractAddress`;
   - `eth_getCode`;
   - runtime hash, init-code hash;
   - proxy detection;
   - template match.
4. Idempotent upsert into `discovery_queue` by `(chain_id, address)`.
5. If matched, still `triage`; a human links to a deployment request and verifies evidence.
6. Record counts, errors, checkpoint, start/end.
7. Alert on unknown/high-risk discoveries, deployer not in allowlist, code hash mismatch, proxy upgrade, role change, pause.
8. Nightly backfill + real-time subscription; re-run failed ranges.

The demo worker implements this flow and a deterministic `--mock` mode. It does not auto-create product instances from chain discovery, by design.

### 7.4 Making sign-off enforceable

A registry approval is **business evidence**. It is not a transaction signature. To make it enforceable:

- The deployment service account is an HSM-backed identity; the HSM policy requires a signed deployment manifest that includes the approval bundle hash.
- The manifest is produced only by the CI/CD pipeline after the registry reports **Ready**.
- Besu account permissioning allows only the deployment service (and factory) to deploy.
- Admin/upgrade roles are held by a Safe + Timelock; execution requires quorum and delay.
- The registry watches the chain and raises an incident if a deployment appears without an approved manifest.
- The approval bundle hash is anchored on-chain (EAS or a small registry anchor contract) so it cannot be silently altered later.

This is the difference between “we have a workflow” and “the workflow controls the key.”

### 7.5 FireFly under Kaleido

FireFly is the contract manager/API and event-listener layer; Kaleido is the managed chain, permissioning and HSM/KMS signing layer. The registry remains the pre-chain control plane. A deployment should only be submitted after the registry returns `Ready` and a signed manifest; FireFly/EthConnect then submits through the Kaleido signing identity, and the sync worker links the receipt address, block and runtime hash back to the same request ID. The full sequence, field mapping, idempotency, failure handling and security controls are in `docs/firefly-kaleido-integration.md`.

---

## 8. Business sign-off model

### 8.1 Objects that need approvals

| Object | Example | Gates |
|---|---|---|
| **Template** | CMTAT 3.0.0, RuleEngine 1.0.0 | Architecture, Security, Audit evidence, Legal/licence, Sourcing/lifecycle |
| **Deployment request** | UBGX Luxembourg on Besu prod | Business, Product, Compliance, Legal, Risk, Security, Operations, CAB; plus DPO/Model Risk for critical |
| **Change request** | Upgrade implementation, change max holders, rotate oracle, pause | Business, Compliance, Risk, Security, Operations, CAB; DPO/Model Risk for critical |
| **Emergency change** | Pause during incident | Incident commander + business + security + compliance; retrospective CAB within 24h |
| **Instance exception** | EOA admin, missing evidence | Risk acceptance with owner and expiry |
| **Incident closure** | Post-mortem and remediation | Business, Risk, Security, Internal Audit observation |

### 8.2 Risk-tiered approval matrix (demo policy)

| Risk | Deployment gates |
|---|---|
| **Low** | Business Owner → Platform Operations |
| **Medium** | Business Owner → Compliance → Operational Risk → Security → Platform Operations |
| **High** | Business Owner → Product Owner → Compliance → Legal → Operational Risk → Security → Platform Operations → CAB |
| **Critical** | High + Data Protection + Model Risk (10 gates) |

Template gates and change gates follow the same pattern. The policy is data, not hard-coded workflow: `approval_policy(object_type, risk_tier, gate, required_role, sequence, blocking)`.

### 8.3 Controls that make sign-off meaningful

- **Role + scope**: the actor must hold an active role for the org unit or an ancestor; p-marco cannot approve a Luxembourg legal gate just because he is a product owner.
- **Segregation of duties**: the requester cannot approve their own deployment/change. Enforced by a database trigger and the API.
- **Gate order**: earlier blocking gates must be approved first.
- **Evidence**: comments + evidence URI/hash; approved templates/deployments should not be a click without a link.
- **Expiry**: approvals and attestations expire; a stale audit cannot support a new deployment.
- **Readiness**: final deployment approval is blocked if the template is not approved, the audit is missing/expired, or a rejection exists.
- **Delegation**: explicit, time-bound, logged; not a shared account.
- **Emergency path**: retrospective approval, incident link, regulator notification assessment.
- **Internal Audit**: read-only access to the immutable audit log and evidence bundles; not an approver of business decisions.
- **On-chain execution evidence**: Safe transaction hash / timelock execution hash linked to the change request.

### 8.4 Sign-off bundle anchoring

For each approved deployment/change, build a canonical JSON bundle:

```json
{
  "object_type": "deployment",
  "object_id": "DR-2026-0051",
  "template_hash": "0x…",
  "config_hash": "0x…",
  "manifest_hash": "0x…",
  "approvals": [{"gate": "LEGAL", "person": "p-daniel", "at": "…", "evidence_hash": "0x…"}],
  "policy_version": "2026.1",
  "created_at": "…"
}
```

Hash it (SHA-256/Keccak-256), store the hash in the registry and anchor it on a permissioned chain (or EAS). Do **not** put names, comments or documents on a public chain. The chain proves the bundle existed and was not changed; the off-chain store proves the content under access control.

---

## 9. Gaps in the current plan

This is the “what are we missing?” list I would put in front of the steering committee.

| # | Gap | Why it matters | Recommended fix |
|---|---|---|---|
| 1 | **Deployer identity and key custody** | An address is not an accountable person; a compromised EOA can deploy anything. | HSM-backed service identities, CI/CD OIDC, deployer allowlist, no personal EOAs, key rotation and leaver process. |
| 2 | **Template vs deployment recipe vs instance vs product** | Reuse and reporting break if these are conflated. | Four-layer model; `instance_kind` and `representation`; do not count implementations as products. |
| 3 | **Source verification and reproducible builds** | Bytecode hash alone does not prove the source matches. | Sourcify/Blockscout, exact-match attestation, pinned compiler, SBOM, reproducible build in CI. |
| 4 | **Proxy / upgrade graph** | Upgrades change risk without changing the address. | EIP-1967 slot reading, implementation link, upgrade history, storage-layout evidence, timelock. |
| 5 | **Public vs private representation** | A public token and a ledger mirror can double-count supply/reserve. | `representation` + reserve pool + `counts_toward_reserve`; reconcile total supply per pool. |
| 6 | **Sign-off quality** | A click without role, scope, evidence and SoD is not a control. | Policy-as-data, role/scope, gate order, evidence hash, expiry, delegation, emergency path. |
| 7 | **Enforcement outside the registry** | The registry cannot stop a key from deploying. | Besu permissioning, HSM policy, factory allowlist, Safe/Timelock, CI/CD gate. |
| 8 | **Evidence expiry and renewal** | Audits, insurance, legal opinions and proof-of-reserve go stale. | Attestation register with expiry, alerts, blocking readiness, renewal workflow. |
| 9 | **Unknown-contract reconciliation** | Shadow deployments and clones are the biggest blind spot. | Discovery queue, chain sync, deployer allowlist, quarantine, incident playbook, coverage KPI. |
| 10 | **Runtime monitoring** | A contract can be paused, upgraded, re-owned or drained after approval. | Index events, alert on admin/role/upgrade/pause, monitor reserve and supply, SIEM integration. |
| 11 | **Legal document linkage** | Terms/prospectus/legal opinion are usually in a shared drive, not linked to the address. | Document register with hash, URI, validity, on-chain anchor, retention. |
| 12 | **Tokenized-gold specifics** | Gold is not just an ERC-20; title, allocation and audit matter. | Reserve pool, bar list, LBMA refinery, vault, insurance, auditor, proof-of-reserve, redemption terms, oracle. |
| 13 | **DORA / MiCA / Basel mapping** | Regulators ask for evidence, not screenshots. | Control framework mapping, register-of-information export, incident reporting fields, outsourcing/third-party links. |
| 14 | **CMDB / GRC / SIEM integration** | A standalone registry becomes stale. | ServiceNow CI link, GRC control/evidence sync, SIEM alerts, CMDB ownership reconciliation. |
| 15 | **Data quality and identifiers** | Duplicate addresses, wrong checksums and chain confusion break reporting. | CAIP-2/CAIP-10 IDs, EIP-55 checksums, canonical template hashes, dedupe rules, data steward. |
| 16 | **Non-EVM future** | Canton/Solana/Tezos do not share EVM semantics. | Chain-agnostic core + adapter model; do not force EVM fields. |
| 17 | **Supply-chain risk** | Open-source templates, npm dependencies and compilers can be compromised. | SBOM, dependency pinning, licence review, maintainer risk, vendor/OSS intake. |
| 18 | **Operating model** | A registry without an owner becomes a graveyard. | Registry owner, taxonomy council, data stewards, SLAs, KPIs, chargeback, training. |
| 19 | **Testing and recovery** | Unit tests do not prove upgrade/rollback safety. | Fork tests, invariant tests, formal verification where material, rollback rehearsal, disaster recovery. |
| 20 | **Privacy / PII** | On-chain data is forever and public on public chains. | No PII on-chain; hashes and privacy groups; DPO sign-off; data-retention policy. |

### 9.1 What I would change in the current plan, in priority order

1. **Make the registry the control plane, not a catalogue.** Every deployment must be linked to an approved template, a request, a manifest, a sign-off bundle and evidence.
2. **Add the four-layer model and proxy/supporting kinds before adding more contract types.** Otherwise the inventory will be wrong on day one.
3. **Add reconciliation and unknown-contract handling in the MVP.** Coverage and shadow deployments are the first questions audit will ask.
4. **Make sign-off policy data-driven and risk-tiered.** Do not hard-code one eight-step workflow for every contract.
5. **Separate business approval from on-chain execution.** Link Safe/Timelock tx hashes as execution evidence.
6. **Enforce with permissioning/HSM/CI, not with a UI warning.** The registry is detective; the key policy is preventive.
7. **Do not build an explorer.** Integrate Sourcify/Blockscout and focus on the bank-specific data model.
8. **Treat tokenized gold as a product with a reserve pool, not just a token.** Supply, bars, vault, auditor, insurance, redemption and legal title must be in scope.
9. **Add DORA/MiCA/Basel fields early.** Retrofitting regulatory mapping is expensive.
10. **Start with one product/division, then platformize.** Gold is a good lighthouse because it exercises legal, reserve, compliance and cross-network issues.
11. **Make data quality a first-class workstream.** CAIP-10, EIP-55, canonical hashes, owner/org hierarchy, dedupe.
12. **Build the operating model with the platform.** Taxonomy council, data steward, change board, SLAs, KPIs and funding.

---

## 10. Roadmap

| Phase | Duration | Scope | Exit criteria |
|---|---|---|---|
| **0. Foundation** | 4–6 weeks | Taxonomy, data model, risk tiers, approval matrix, identifier standard, current-state inventory of gold contracts, legal/regulatory mapping | Signed-off taxonomy and policy; baseline coverage of the gold estate; named owners. |
| **1. MVP** | 1 quarter | Template + instance registry, deployment requests, sign-off workflow, Besu/ETH sync, unknown queue, evidence expiry, UI, export | 100% of gold production contracts registered; unknown queue triaged; all high-risk deployments have complete gates; audit walkthrough passes. |
| **2. Control integration** | 1–2 quarters | Sourcify/Blockscout verification, ServiceNow CI link, GRC/DORA mapping, SIEM alerts, Safe/Timelock execution evidence, reserve reconciliation, incident workflow | Automated coverage >95%; evidence freshness >90%; MTTR reduction; DORA export tested. |
| **3. Scale** | 2 quarters | More divisions/products, multi-chain, factory/clone automation, policy-as-code, on-chain bundle anchoring, non-EVM adapter, chargeback | Reuse >60%; deployment cycle reduced; no unapproved production deployments; platform funded as a shared service. |

### Success metrics

- **Coverage:** registered logical contracts / (registered + unknown) ≥ 95%.
- **Template reuse:** deployments from approved templates / total deployments ≥ 80%.
- **Approval completeness:** high/critical deployments with all blocking gates approved before deployment = 100%.
- **Evidence freshness:** valid audits/attestations for in-scope templates ≥ 95%.
- **Shadow deployments:** unapproved production deployments per quarter → 0.
- **Time-to-deploy:** median elapsed time from approved request to production, down 30–50%.
- **Audit reuse:** percentage of deployments using an already-audited template without duplicate audit.
- **MTTR:** mean time to identify owner/authority/dependency during an incident, down 50%.
- **Cost per deployment:** registry run cost / deployments per year.

---

## 11. What the demo proves — and what it does not

### Proves

- The schema can represent templates, deployments, implementations, supporting contracts, proxies, links, roles, reserve pools and evidence.
- A template can have multiple deployments across chains without duplicating the template record.
- Proxy → implementation and token → rule engine / identity / oracle / reserve / Safe links are queryable.
- Sign-off policy can be risk-tiered, ordered, role/scope-checked and SoD-protected.
- Final deployment approval is blocked by template/audit readiness.
- Reserve supply can be reconciled without double-counting UAT/retired/mirror tokens.
- Unknown on-chain contracts are surfaced and quarantined, not silently ignored.
- The UI can show a 360 view without a graph database or an explorer.

### Does not prove

- Real Besu privacy-group behaviour, permissioning or finality/reorg handling (no node in this environment).
- Real Sourcify/Blockscout verification calls (links are modelled).
- Production-grade authn/authz, encryption, WORM storage, high availability or disaster recovery.
- Legal enforceability of tokenized gold, CMTAT or any product.
- Regulatory completeness for DORA, MiCA, Swiss DLT Act or Basel; the mapping is a starting point, not a legal opinion.
- That the demo’s risk tiers and approval matrix match the bank’s actual policy; they are illustrative.

---

## 12. Persona review (pstack-style council)

The prototype is reviewed by eight roles that mirror a bank's compliance and control stack:

- Business Owner / Product
- Compliance / AML & Sanctions
- Legal / Regulatory
- Operational Risk / Internal Audit
- CISO / Smart Contract Security
- Data Protection / Privacy
- Finance / Treasury / Reserve
- Regulator / External Audit

Each role has a mandate, decision rights and evidence asks. Findings are persisted in `persona_finding` and shown in the **Council** view. The review deliberately records what is still open: no IdP/MFA, 141 approved gates with placeholder evidence, missing legal-title/insolvency opinions, sanctions/travel-rule records, DPIA/privacy-group evidence, DORA export, upgrade proof and redemption/complaint workflows.

The changes driven by the review include:

- signing identities and deployer allowlists;
- complete template gates for approved high/critical templates;
- a four-eyes rule (one person cannot approve two blocking gates on the same object);
- append-only audit-log triggers;
- compliance profiles covering legal title, AML, sanctions, travel rule, DPIA, DORA, redemption, complaints and retention;
- ICT third-party / DORA dependency registers;
- reserve bar reconciliation and supply-delta views;
- an explicit evidence-gap view and Council dashboard.

See `PSTACK.md` and `docs/persona-review.md`.

---

## 13. Sources

- Sourcify contract dataset and verification: <https://docs.sourcify.dev/docs/repository/>
- Blockscout open-source explorer: <https://www.blockscout.com/>
- EBSI Trusted Contracts Registry: <https://hub.ebsi.eu/api/trusted-contracts-registry/trusted-contracts-registry-api-v-1>
- Hyperledger FireFly: <https://github.com/hyperledger-firefly/firefly> and FFI format: <https://hyperledger.github.io/firefly/head/reference/firefly_interface_format>
- EthPM specification: <https://ethpm.github.io/ethpm-spec/>
- Ethereum Attestation Service: <https://attest.sh/>
- ONCHAINID: <https://github.com/onchain-id/solidity>
- ERC-3643 (T-REX): <https://eips.ethereum.org/EIPS/eip-3643>
- CMTAT: <https://github.com/CMTA/CMTAT>; CMTA RuleEngine: <https://github.com/CMTA/RuleEngine>
- EEA EthTrust Security Levels: <https://entethalliance.org/specs/ethtrust-sl/>
- EIP-1167 minimal proxy: <https://eips.ethereum.org/EIPS/eip-1167>
- EIP-1967 proxy slots: <https://eips.ethereum.org/EIPS/eip-1967>
- EIP-1014 CREATE2: <https://eips.ethereum.org/EIPS/eip-1014>
- ERC-1822 UUPS: <https://eips.ethereum.org/EIPS/eip-1822>
- Besu JSON-RPC API: <https://besu.hyperledger.org/public-networks/reference/api>
- Besu private networks: <https://besu.hyperledger.org/private-networks/>
- CAIP-10 account IDs: <https://github.com/ChainAgnostic/CAIPs/blob/master/CAIPs/caip-10.md>
- Safe Transaction Service: <https://docs.safe.global/>
- OpenZeppelin Upgrades: <https://docs.openzeppelin.com/upgrades-plugins/>
- DORA: <https://www.eiopa.europa.eu/digital-operational-resilience-act-dora_en>
- MiCA: <https://www.esma.europa.eu/esmas-activities/digital-finance-and-innovation/markets-crypto-assets-regulation-mica>
- Swiss DLT legislation / FINMA: <https://www.finma.ch/en/authorisation/fintech-and-dlt/>
- Basel Committee crypto-asset exposures (SCO60): <https://www.bis.org/bcbs/publ/d545.htm>
- LBMA Good Delivery: <https://www.lbma.org.uk/good-delivery>

*Research current as of October 2026. Verify current versions, chain support and licence terms before production use.*
