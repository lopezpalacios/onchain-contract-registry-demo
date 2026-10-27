# Build Prompt — Financial Institution Smart Contract Inventory & Control Registry

Use this prompt with a capable coding agent. It is written to produce a runnable, dependency-light prototype, not a slide deck.

---

## 1. Role

You are a senior platform engineer at a financial institution, working with the software-inventory team, digital assets, cyber security, operational risk and compliance.

You have been asked to prototype a **smart contract registry** for EVM contracts. The bank already has a software inventory/CMDB, but it cannot answer:

- Which on-chain contracts belong to which approved template?
- Which business owner, legal entity, division and product do they belong to?
- Which deployment was approved, by whom, with what evidence?
- Is the deployed code still what was approved?
- Which public/private/mirror representations exist, and are they double-counting supply or reserves?
- What is running on the permissioned Besu network that was never registered?

Build a working local demo that answers those questions.

---

## 2. Mission

Build a local, runnable prototype with:

- **SQLite** as the database.
- **Python standard library only** for the API/server.
- **Vanilla HTML/CSS/JavaScript** for the UI. No React, no build step, no CDN.
- **A real Besu/EVM JSON-RPC discovery adapter** that also supports a deterministic mock mode.
- **A pstack-style council** of banking compliance, legal, risk, security, DPO, finance and business roles, with owned findings, compliance profiles and evidence gaps.
- **A four-step onboarding wizard** that creates the pre-chain registration, computes risk/gates and records evidence gaps; deployment authority defaults to FireFly under Kaleido.
- **Tests**.
- **Research and design documents**.
- **An honest business case**.

The demo must run with:

```bash
python3 scripts/build_db.py
python3 app.py
# open http://127.0.0.1:8765
```

No Docker, no Node, no pip install, no external services.

---

## 3. Non-goals

- Do not build a block explorer.
- Do not connect to a real bank network.
- Do not use real customer, employee, contract, address or reserve data.
- Do not put PII on-chain.
- Do not auto-approve a contract because it matches a bytecode hash.
- Do not claim legal or regulatory compliance.
- Do not invent production-hardening that the prototype does not have.

All names, people, addresses, hashes, contracts and incidents must be fictional. Put a clear disclaimer in the README.

---

## 4. Required architecture

Use four layers, not one:

1. **Template** — the approved code artifact. Fields include template key, version, category, contract type, source repo/path/commit, compiler/EVM, licence, init-code hash, runtime-code hash, ABI hash, audit status/provider/validity, EthTrust level, default risk tier, owner org unit, status.
2. **Deployment request** — the business intent: template, chain, environment, requester, business owner, org unit, product, legal entity, jurisdiction, risk tier, config hash, init params, salt, manifest hash, status, change ticket, target window.
3. **Contract instance** — the on-chain object: chain, address, template, `instance_kind` (`logical`, `implementation`, `supporting`), `representation` (`native`, `mirror`, `wrapped`, `receipt`, `not_applicable`), deployment request, tx, deployer, block, salt, code hashes, proxy type, implementation/admin/beacon, lifecycle status, business owner, legal entity, jurisdiction, classification, risk tier, criticality, privacy group, canonical flag, supersedes, verification status/provider/URL.
4. **Product / service** — expressed through the instance fields and links, not a separate duplicate table if that adds complexity. A product can have multiple instances across chains/representations.

Supporting tables:

- chain
- org_unit, person, role_assignment
- standard, template_standard, template_dependency, template_parameter
- software_ci, template_ci
- approval_policy, signoff
- instance_parameter
- token_metadata, reserve_pool, reserve_snapshot, gold_bar
- contract_link
- instance_role
- document
- attestation
- onchain_event
- change_request
- incident
- control, instance_control
- sync_run, discovery_queue
- audit_log

Relationships must include:

- `template 1 ── * contract_instance`
- `contract_instance * ── * contract_instance` via `contract_link`:
  `delegates_to`, `admin_controlled_by`, `uses_rule_engine`, `uses_identity_registry`,
  `reads_trusted_issuers`, `reads_claim_topics`, `contains_rule`, `prices_from`,
  `reads_price_feed`, `settles_with`, `collateralised_by`, `attested_by`,
  `deployed_by_factory`, `mirrors`, `guards`, `supersedes`.
- `deployment_request 1 ── * signoff`
- `template/instance 1 ── * document/attestation`
- `discovery_queue` for unknown on-chain contracts.

---

## 5. Database requirements

- Use SQLite `STRICT` tables.
- Enable foreign keys.
- Enforce `UNIQUE(chain_id, address)` on instances.
- Enforce `UNIQUE(template_key, version)`.
- Enforce one current reserve snapshot per reserve pool with a partial unique index.
- Add indexes for template, chain, instance kind, sign-off object, attestation expiry and audit log.
- Add triggers that prevent:
  - a requester approving their own deployment;
  - a requester approving their own change;
  - an actor without an active role approving or rejecting a gate.
- Add application-level checks for:
  - role scope (the actor’s role must cover the request org unit or an ancestor);
  - gate order (earlier blocking gates must be approved);
  - final deployment readiness (template approved, independent audit valid, no rejection);
  - final template approval (independent audit valid).
- Keep an append-only `audit_log`.

Views required:

- `v_inventory` (logical only)
- `v_template_usage` (all instances, with logical/live counts)
- `v_gate_status` (policy sequence, next gate, eligible role)
- `v_deployment_readiness`
- `v_pending_approvals`
- `v_attestation_alerts`
- `v_unlinked_discoveries`
- `v_contract_links`
- `v_token_reserve`
- `v_control_coverage`
- `v_control_exceptions`
- `v_chain_health`
- `v_role_holders`

Seed enough data to exercise the model:

- 3 chains: Ethereum mainnet, Besu production, Besu UAT.
- A fictional financial institution with divisions, legal entities, people and role assignments.
- **26 templates**, including:
  - CMTAT 2.3.0 (deprecated), CMTAT 3.0.0 (audited), CMTAT 3.2.0 (draft, self-assessed, blocked), CMTAT UUPS 3.0.0.
  - CMTA RuleEngine, max-holders rule, country-restriction rule.
  - ERC-3643 identity/trusted-issuer/claim-topics registries.
  - CMTA DvP, escrow, ERC-4626 vault, collateral vault, CHF deposit token.
  - ERC-1967 proxy, CMTAT factory, Multicall3, Timelock, Safe, Chainlink feed, gold oracle adapter, proof-of-reserve registry.
  - Draft CCIP adapter, ERC-4337 account, Groth16 verifier.
- **25 contract records**: 16 logical, 1 implementation, 8 supporting.
- **Tokenized gold**: three CMTAT 3.0.0 deployments across two chains (public UUPS on Ethereum, ledger token on Besu prod, UAT clone), plus a retired v2 token.
- **Reserve pools**: public and ledger pools, separate attested snapshots, 101% coverage, 125,000g supply / 126,250g gold; UAT and retired supply excluded.
- **Approvals**: high-risk deployment has 8 gates; critical has 10; template and change policies; pending, approved and blocked examples.
- **Attestations**: valid audit, expiring audit, expired self-assessment, proof of reserve expiring in 19 days, insurance, legal opinion, DORA entry.
- **Unknown contracts**: a 94% CMTAT clone on Ethereum mainnet quarantined as critical; two unknown Besu contracts; a linked Multicall; a linked factory clone.
- **Controls**: 10 controls, exceptions for an EOA admin and a backfilled DvP deployment, open incidents.
- **Events**: Upgraded, AdminChanged, RoleGranted, Transfer, RuleEngineChanged, ReserveAttested, Paused, Unpaused, OwnershipTransferred, ContractDeployed, AnswerUpdated.

---

## 6. Sign-off model

Policy is data, not hard-coded workflow.

Example deployment matrix:

- **Low**: Business Owner → Platform Operations.
- **Medium**: Business Owner → Compliance → Operational Risk → Security → Platform Operations.
- **High**: Business Owner → Product Owner → Compliance → Legal → Operational Risk → Security → Platform Operations → Change Advisory Board.
- **Critical**: High + Data Protection + Model Risk (10 gates).

Template policy:

- Architecture → Security → Audit evidence (Operational Risk) → Legal → Sourcing/Platform Operations; add Data Protection for critical.

Change policy:

- High: Business → Compliance → Risk → Security → Operations → CAB.
- Critical: add Data Protection and Model Risk.

Rules:

- The requester cannot approve.
- The actor must hold an active role, with scope covering the org unit or an ancestor.
- Gates are ordered; earlier blocking gates must be approved.
- A final deployment approval is blocked if the template is not approved, the audit is missing/expired, or a gate was rejected.
- A final template approval is blocked if the audit is self-assessed, internal-only where independent assurance is required, or expired.
- Approvals have comments and an evidence URI/hash.
- Emergency changes are allowed but must link an incident, use a retrospective CAB, and assess regulatory reporting.
- Internal Audit is read-only, not a business approver.

The UI must allow an eligible actor to approve/reject a pending gate and must show a clear error for wrong role, wrong order, self-approval or blocked readiness.

---

## 7. Besu / EVM discovery

Implement `scripts/besu_sync.py` using `urllib` only.

Requirements:

- Check `eth_chainId` against the registry chain row.
- Walk a block range or poll from a checkpoint.
- Find contract-creation transactions (`to == null`).
- Read `eth_getTransactionReceipt`, status, `contractAddress`, logs.
- Read `eth_getCode`; compute Keccak-256 runtime hash.
- Compute init-code hash from transaction input.
- Detect:
  - EIP-1167 minimal proxies (prefix `363d3d373d3d3d363d73`, embedded address);
  - EIP-1967 implementation slot `0x3608…bbc`;
  - EIP-1967 admin slot `0xb531…6103`;
  - EIP-1967 beacon slot `0xa3f0…3d50`;
  - beacon `implementation()` via `eth_call`.
- Match templates by runtime hash, init-code hash, or proxy implementation hash.
- Write unknown/matched contracts to `discovery_queue`, never auto-approve.
- Record a `sync_run` with counters, errors, checkpoint, start/finish.
- Support `--mock` to insert one deterministic unknown contract for the UI button.
- Support `--inspect <address>`, `--dry-run`, `--from-block`, `--to-block`, `--poll`.
- Document private Besu caveats: mTLS/OIDC, no public 8545, read-only account, privacy-group-aware `priv_*` APIs, finality buffer, reorgs.

The registry must be described as **detective**, not preventive. Enforcement belongs to Besu permissioning, HSM policy, CI/CD OIDC, factory allowlists and Safe/Timelock.

---

## 8. API

Implement a stdlib `ThreadingHTTPServer`:

- `GET /api/health`
- `GET /api/summary`
- `GET /api/contracts` with `q`, `risk`, `chain`, `status`
- `GET /api/contracts/<id>`
- `GET /api/templates`
- `GET /api/templates/<id>`
- `GET /api/approvals`
- `GET /api/registrations`
- `GET /api/reference`
- `POST /api/onboarding`
- `GET /api/discovery`
- `GET /api/controls`
- `GET /api/audit`
- `POST /api/signoffs/<id>/decision` with `{decision, actor_id, comments}`
- `POST /api/sync` for the demo mock sync

The contract detail payload must include template, token metadata, reserve snapshot, parameters, roles, links (in/out), documents, attestations, events, controls, changes, incidents, sign-offs and audit entries.

The approval payload must include gates, sequence, blocking flag, decision, approver, comments, evidence, next gate and eligible actors for the next gate.

Security: bind to `127.0.0.1`; no auth/TLS; state clearly that it is local-only.

---

## 9. UI requirements

Design language: **financial institution** — deep black, white, warm grey, one red accent, Helvetica/Arial, uppercase micro-labels, 2px radius, thin rules, restrained shadows, no gradients/glassmorphism, no SaaS purple, no emoji icons in the product UI.

Views:

1. **Overview** — 6 KPIs, risk donut, template category bars, tokenized-gold reserve card, approval queue, attention list, recent deployments.
2. **Registration** — pre-chain record (template, request, config/manifest hash and approvals) linked to the deployed address, transaction, block, proxy/implementation and runtime-code hash; pre-chain vs linked rows must be distinct.
3. **Onboarding** — four-step wizard: purpose, code source, chain/environment, user impact, risk, FireFly/Kaleido authority, evidence; review and create a pre-chain request.
4. **Inventory** — search + risk/chain/status filters, table with product, template/version, chain, owner/division, risk, audit state, verification, status.
5. **Templates** — searchable card grid + table; show deployments, chains, audit, status, standards, category.
6. **Approvals** — KPIs, deployment cards with gate rail, progress, readiness and review buttons; template and change approvals.
7. **Council** — pstack-style persona cards, findings, compliance coverage, evidence gaps, ICT third parties, reserve reconciliation and deployer risk.
8. **Reconciliation** — chain health, unknown-contract queue, sync runs, Besu ingestion flow explanation, inspect modal.
9. **Controls** — control coverage bars, expiring evidence, exceptions, incidents, reserve table, deployment readiness.

Detail modals:

- Contract 360: summary, compliance profile, dependencies, governance, evidence, on-chain events, changes/incidents.
- Template detail: overview, deployments, standards, evidence, parameters.
- Discovery detail: address, code hash, deployer, classification, notes.
- Approval modal: eligible actor select, comment, approve/reject, error handling.

Use only vanilla JS; no frameworks. Provide toast feedback, copy-address, Escape-to-close, responsive layout.

---

## 10. Tests

Add `unittest` tests covering:

- schema integrity and foreign keys;
- template → deployment linkage;
- every logical instance has an owner/org/risk;
- public UUPS proxy binding to implementation;
- reserve coverage and no double-counting;
- readiness blocks an unaudited template;
- next-gate sequence;
- database SoD trigger;
- database role-eligibility trigger;
- duplicate chain+address rejected;
- unknown contracts visible;
- attestation alerts;
- control exceptions traceable;
- approved requests have complete gates;
- dependency graph and factory links;
- API rejects wrong role;
- API accepts eligible approver;
- final deployment gate cannot bypass a blocked template;
- final template approval requires an independent audit;
- mock sync is idempotent.

Target: 30 passing tests, including reserve bar reconciliation, complete template gates, four-eyes, append-only audit log, persona/council data and deployer-risk visibility.

---

## 11. Research and docs

Write `docs/registry-blueprint.md` covering:

- No single open-source registry covers template + deployment + sign-off + evidence + CMDB.
- Compare Sourcify, Blockscout, EBSI Trusted Contracts Registry, Hyperledger FireFly, EthPM, EAS, ONCHAINID/ERC-3643, CMTAT + RuleEngine, Safe Transaction Service, 4byte, Baseline Protocol.
- Reference architecture and source-of-truth hierarchy.
- Four-layer model, instance kinds, representations.
- Contract taxonomy and missing types.
- Template/deployment matching signals, proxies, clones, deterministic deployments.
- Besu JSON-RPC table and private-network caveats.
- Sign-off model and enforcement outside the registry.
- Gap list and prioritized recommendations.
- Roadmap and success metrics.
- Sources.

Write `docs/persona-review.md` and `PSTACK.md`:

- Eight roles: Business, Compliance/AML, Legal/Regulatory, Operational Risk/Internal Audit, CISO/Security, DPO, Finance/Reserve, Regulator.
- Each role has a mandate, decision rights and core questions.
- Findings must name actual records and have severity, owner, due date and evidence.
- Show what was remediated and what remains open.
- The Council UI must show open findings, compliance profiles, evidence gaps, ICT dependencies, reserve reconciliation and deployer risk.

Write `docs/business-case.md`:

- Cost of inaction.
- Value drivers with formulas.
- Illustrative base case, conservative case and upside.
- Cost model.
- KPIs.
- Funding options.
- Regulatory mapping (DORA, MiCA, Swiss DLT/FINMA, Basel, AML, GDPR, SOX, EthTrust).
- Risks and decision ask.
- State clearly that efficiency alone does not pay back; risk/regulatory + revenue is the case.

Add a `scripts/business_case.py` model with NPV, payback and ROI.

Add `docs/example-queries.sql` with 18 useful queries.

---

## 12. Acceptance criteria

- `python3 scripts/build_db.py` builds `data/registry.db` with `PRAGMA integrity_check = ok`.
- `python3 app.py` serves the UI at `http://127.0.0.1:8765`.
- All six views render with no console errors.
- Contract, template, discovery and approval modals work.
- An eligible approver can approve a pending gate; the nav pending count decreases.
- A wrong role is rejected.
- A final approval cannot bypass a blocked template/audit.
- `python3 -m unittest discover -s tests -v` passes 30 tests.
- The onboarding wizard creates a pre-chain request with no address; FireFly/Kaleido authority is recorded. A linked request shows address, tx, block and hash match.
- `python3 scripts/besu_sync.py --mock --chain ch-besu-prod` writes a discovery and sync run.
- `python3 scripts/business_case.py` prints three scenarios.
- README clearly states: fictional data, local demo, no auth/TLS, no real Besu node tested, not legal advice, no bank affiliation.

---

## 13. Output tree

```text
onchain-contract-registry-demo/
├── README.md
├── PROMPT.md
├── PSTACK.md
├── NOTICE.md
├── app.py
├── registry/
│   ├── schema.sql
│   ├── seed.sql
│   ├── views.sql
│   └── keccak.py
├── scripts/
│   ├── build_db.py
│   ├── besu_sync.py
│   ├── business_case.py
│   └── export_stack.py
├── web/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── tests/
│   └── test_registry.py
├── docs/
│   ├── registry-blueprint.md
│   ├── persona-review.md
│   ├── firefly-kaleido-integration.md
│   ├── business-case.md
│   └── example-queries.sql
└── data/
    └── registry.db
```

---

## 14. One-shot condensed prompt

> Build a runnable local smart-contract registry demo for a fictional financial institution. Use SQLite, Python stdlib and vanilla JS. Model templates, deployment requests, on-chain instances (logical/implementation/supporting; native/mirror/wrapped/receipt), proxy links, reserves, evidence, changes, incidents and discovery. Seed CMTAT 3.0 tokenized gold on Besu + Ethereum, a rule engine, identity registries, DvP, escrow, CHF deposit, Safe/Timelock, oracle, proof-of-reserve, factory, multicall, plus draft CCIP/ERC-4337/ZK templates. Implement risk-tiered sign-offs with role/scope, segregation of duties, four-eyes, gate order, evidence expiry and readiness blocking. Add a Besu JSON-RPC discovery worker with EIP-1967/1167 detection and an unknown-contract queue. Add a pstack-style Council of eight banking roles, compliance profiles, signing identities, ICT third parties, reserve reconciliation and explicit evidence gaps. Build a Swiss-style UI with overview, registration, onboarding, inventory, templates, approvals, council, reconciliation and controls, plus detail modals. The onboarding wizard must ask purpose, code source, chain, user impact, risk, deployment authority (default FireFly under Kaleido) and evidence, then create a pre-chain request with computed gates and visible evidence gaps. Write 30 tests, research open-source registries, a gap analysis and an honest business case. No real bank data; local-only; no auth/TLS; no explorer rebuild.

---

## 15. Safety and publication

Before publishing:

- Replace all real bank, employee, customer, contract, address and reserve data with fictional values.
- Remove secrets, API keys, RPC credentials and internal URLs.
- Check the README disclaimer.
- Add a licence appropriate to your organisation if you intend others to reuse the code.
- Do not present the demo as a production control or as legal/regulatory advice.
