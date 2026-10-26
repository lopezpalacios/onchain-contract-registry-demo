# Smart Contract Inventory & Control Registry

A working SQLite prototype of a bank-grade registry for **smart contract templates, on-chain deployments, business sign-offs, evidence and reconciliation**.

**Public gist:** https://gist.github.com/lopezpalacios/90e21f50bfbe94962eb4284c3f5cae88

The demo is built around a fictional financial institution and a tokenized-gold estate: CMTAT 3.0.0 on a permissioned Besu ledger and on Ethereum mainnet, CMTA RuleEngine rules, ERC-3643 identity registries, a DvP settlement contract, a CHF deposit token, an escrow, a collateral-vault template, Safes, timelocks, oracles and proof-of-reserve. A **pstack-style Council** view records what Compliance, Legal, Operational Risk, Security, DPO, Finance and the business owner still do not accept.

> **Demo only.** All banks, people, addresses, hashes, contracts and incidents are fictional. This is not legal, regulatory or investment advice. The visual language is Swiss-style (black/white/red, Helvetica, 2px radius).

---

## Quick start

```bash
git clone https://github.com/lopezpalacios/onchain-contract-registry-demo.git
cd onchain-contract-registry-demo
python3 scripts/build_db.py          # creates data/registry.db from schema + seed + views
python3 app.py                       # http://127.0.0.1:8765
```

No third-party Python packages are required. Python 3.11+ and SQLite 3.35+ are enough.

```bash
python3 -m unittest discover -s tests -v
```

The current build has **26 templates**, **25 contract records** (16 logical product deployments, 1 implementation, 8 supporting contracts), **166 sign-off rows**, **20 persona findings**, **7 compliance profiles**, **5 ICT third parties**, **15 attestations**, **5 discovery items** and **3 chains**.

---

## What to look at in the demo

| View | What it demonstrates |
|---|---|
| **Overview** | Coverage, risk mix, reserve coverage, approval queue, expiring evidence and unknown-contract alerts. |
| **Inventory** | One row per logical deployment; proxy/implementation and supporting contracts are linked, not counted as products. |
| **Templates** | Template catalogue with version, standards, audit state, reuse count and every deployment. |
| **Approvals** | Risk-tiered gates, ordered approvals, role/scope checks, segregation of duties and readiness blocking. |
| **Reconciliation** | Besu/EVM discovery queue, sync runs, chain health, unknown-contract quarantine. |
| **Council** | pstack-style review by eight banking roles: findings, owners, decision rights, compliance profiles, evidence gaps, ICT third parties, reserve reconciliation and deployer risk. |
| **Controls** | Control coverage, exceptions, incidents, reserve attestations and policy-computed deployment readiness. |

Try these flows:

1. Open **Inventory → UBGX Gold Token (Public)**. It is a UUPS proxy; the implementation is a separate on-chain record, and the admin is a 48-hour timelock controlled by a 3-of-5 Safe.
2. Open **Templates → CMTAT Standard 3.0.0**. It has three logical deployments on two chains. Open **CMTAT Standard 3.2.0**; it is blocked because the independent audit is missing/expired.
3. Open **Approvals → UBGX Pilot 3.2**. Business and Compliance approved, but the next gate is blocked by the template. The final CAB gate cannot be completed.
4. Open **Approvals → UBGX Gold Token (Luxembourg)** and review **LEGAL** as Daniel Roth. The wrong actor is rejected; the eligible actor succeeds.
5. Open **Reconciliation**. `disc-001`, `disc-002` and `disc-003` are unknown contracts. `disc-003` is a 94%-similar CMTAT clone on Ethereum mainnet, quarantined as critical.
6. Click **Run Besu sync** to exercise the mock adapter; it writes a new unknown-contract discovery and a sync run.
7. Open **Council**. Review the 20 findings from Compliance, Legal, Operational Risk, Security, DPO, Finance, Business and Regulator. Open a finding/contract to see the compliance profile and signer identity.
8. Open **Controls**. SC-05 is an exception because the country-restriction rule admin is an EOA; SC-04 is an exception because the DvP contract was backfilled without complete CAB evidence. Both are owned and approved.

---

## Repository layout

```
onchain-contract-registry-demo/
├── README.md
├── PROMPT.md                   # build prompt for a coding agent
├── PSTACK.md                   # banking persona review protocol
├── NOTICE.md                   # demo/publication disclaimer
├── app.py                      # stdlib HTTP API + static server
├── registry/
│   ├── schema.sql              # STRICT SQLite schema, constraints, SoD triggers
│   ├── views.sql               # inventory, readiness, approvals, reserves, controls
│   ├── seed.sql                # fictional gold estate, policies, sign-offs, evidence
│   └── keccak.py               # dependency-free Keccak-256 / EIP-55 / selectors
├── scripts/
│   ├── build_db.py             # rebuild data/registry.db
│   ├── besu_sync.py            # real JSON-RPC discovery adapter + mock mode
│   ├── business_case.py        # illustrative NPV/payback/ROI model
│   └── export_stack.py         # text-only source bundle for a gist
├── web/
│   ├── index.html
│   ├── style.css               # Swiss-style design system
│   └── app.js                  # vanilla JS views, modals, approval action
├── tests/test_registry.py      # schema, linkage, SoD, readiness, reserve, API, sync tests
├── docs/
│   ├── registry-blueprint.md   # research, architecture, taxonomy, gaps, roadmap
│   ├── persona-review.md       # council findings, disposition and open gates
│   ├── business-case.md        # value model, scenarios, KPIs, regulatory mapping
│   └── example-queries.sql     # 18 ready-to-run registry queries
└── data/registry.db            # built demo database
```

---

## The data model in one minute

The registry deliberately separates four things that are often conflated:

1. **Template** — an approved code artifact: source repo, commit, compiler, init-code hash, runtime-code hash, audit, EthTrust status, licence, owner and version.
2. **Deployment request** — the business intent: chain, environment, product, legal entity, jurisdiction, risk tier, config hash, manifest hash and target window.
3. **Contract instance** — the on-chain address. It has a kind (`logical`, `implementation`, `supporting`) and a representation (`native`, `mirror`, `wrapped`, `receipt`).
4. **Product / service** — the commercial offering. Several instances can implement one product; a mirror or wrapped representation is not a second reserve claim.

Key relationships:

- `template 1 ── * contract_instance`
- `contract_instance * ── * contract_instance` via `contract_link` (`delegates_to`, `uses_rule_engine`, `uses_identity_registry`, `prices_from`, `reads_price_feed`, `settles_with`, `collateralised_by`, `attested_by`, `deployed_by_factory`, `admin_controlled_by`, `supersedes`)
- `deployment_request 1 ── * signoff`, with `approval_policy` defining the required gates by risk tier
- `contract_instance * ── * attestation` and `document` for evidence
- `discovery_queue` for contracts seen on-chain but not linked to an approved registry record
- `persona`, `persona_finding` for the pstack-style council
- `compliance_profile` for legal/AML/privacy/DORA/redemption evidence
- `signing_identity` for deployer key custody and allowlisting
- `ict_third_party`, `instance_ict` for DORA third-party dependencies

The schema enforces:

- unique `(chain_id, address)`;
- no self-approval by the requester (database trigger);
- an approver must hold an active role matching the gate (database trigger);
- one person cannot approve two blocking gates on the same object (four-eyes trigger + API check);
- application-level gate ordering and scope checks;
- template/audit readiness and complete template gates before the final deployment approval can complete;
- reserve supply and gold amounts linked through a reserve pool, so the same pool cannot be counted twice by accident;
- reserve bars must reconcile to the snapshot and supply delta is visible;
- `audit_log` rejects UPDATE and DELETE (append-only in SQLite).

SQLite is used for a zero-install demo. In production the same model should run on PostgreSQL with row-level security, a WORM audit store, an IdP-backed role model, and field-level encryption/HSM integration for sensitive values.

---

## Besu / EVM discovery

The adapter is a real JSON-RPC worker, not just a mock:

```bash
# Mock mode used by the UI button
python3 scripts/besu_sync.py --mock --chain ch-besu-prod

# Inspect one address without writing
python3 scripts/besu_sync.py \
  --inspect 0x46009f357c42ca5895de915a469cbb56b760411e \
  --chain ch-besu-prod \
  --rpc https://besu-prod.bank.internal:8545

# Backfill a block range
python3 scripts/besu_sync.py \
  --chain ch-besu-prod \
  --rpc https://besu-prod.bank.internal:8545 \
  --from-block 1844300 --to-block 1844400

# Dry run
python3 scripts/besu_sync.py ... --dry-run
```

What it does:

- verifies `eth_chainId` against the registry chain record;
- walks blocks and finds creation transactions (`to == null`);
- reads receipts and deployed runtime code;
- computes Keccak-256 runtime and init-code hashes;
- detects **EIP-1167 clones** and **EIP-1967 implementation / beacon / admin slots**;
- matches templates by runtime hash, init-code hash, or proxy implementation hash;
- writes new/unknown contracts to `discovery_queue` and records an auditable `sync_run` with checkpoint;
- never auto-approves a match. A matched contract still needs a human link to a deployment request and evidence.

Production hardening: put Besu RPC behind mTLS/OIDC, never expose port 8545, use a read-only service account, track privacy-group IDs for private transactions, handle reorgs with a finality buffer, and run the worker as an idempotent checkpointed job. For private Besu state, use the privacy-group-aware `priv_*` APIs or an indexer that is a member of the group; test the exact method set against your Besu version.

---

## API

| Endpoint | Purpose |
|---|---|
| `GET /api/summary` | Dashboard counts, coverage, risk, reserve, alerts, recent deployments |
| `GET /api/contracts` | Logical inventory; supports `q`, `risk`, `chain`, `status` |
| `GET /api/contracts/<id>` | Full 360: template, token, reserve, links, roles, docs, attestations, events, controls, sign-offs |
| `GET /api/templates` | Template catalogue with usage and standards |
| `GET /api/templates/<id>` | Template detail, standards, parameters, deployments, evidence |
| `GET /api/approvals` | Deployment, template and change gates with eligible actors |
| `GET /api/discovery` | Discovery queue, sync runs, chain health |
| `GET /api/controls` | Control coverage, exceptions, incidents, reserves, readiness |
| `GET /api/council` | Persona findings, compliance profiles, evidence gaps, ICT third parties, reserve and deployer risk |
| `POST /api/signoffs/<id>/decision` | `{decision, actor_id, comments}`; validates role, scope, SoD, gate order and readiness |
| `POST /api/sync` | Demo mock Besu sync |

The demo server has no authentication, TLS or CSRF protection. Bind it to `127.0.0.1` only.

---

## Docs

- **[docs/registry-blueprint.md](docs/registry-blueprint.md)** — research on open-source registries, reference architecture, contract taxonomy, template/deployment linkage, Besu integration, sign-off design, gaps and roadmap.
- **[docs/business-case.md](docs/business-case.md)** — value drivers, illustrative business case, KPIs, funding, regulatory mapping and risks.
- **[docs/example-queries.sql](docs/example-queries.sql)** — 18 ready-to-run queries for inventory, reuse, proxies, pending gates, reserves, alerts, exceptions, DORA export and events.
- **[PROMPT.md](PROMPT.md)** — a complete build prompt for reproducing the stack with a coding agent.
- **[PSTACK.md](PSTACK.md)** — the eight-role banking review protocol and what the council changed.
- **[docs/persona-review.md](docs/persona-review.md)** — synthesized findings, dispositions and remaining gate items.
- **[NOTICE.md](NOTICE.md)** — fictional-demo, no-affiliation and production-readiness notice.

---

## Status

- 28 automated tests pass.
- API and UI are smoke-tested with Playwright; no console errors.
- The Besu adapter is tested in mock mode. A real node is not available in this environment; the JSON-RPC path is implemented but should be validated against the bank's Besu version and privacy configuration before use.
- The Council view deliberately shows **141 approved gates with placeholder or missing evidence**, no IdP/MFA, and open legal/AML/DPIA/DORA findings. Do not present the demo as production-ready.
- Source verification is modelled through Sourcify/Blockscout links; no external verification call is made by the demo.

---

## Design credit

The UI follows a Swiss-style visual language: deep black, white, Helvetica-style typography, a single red accent, thin rules, square corners and restrained motion. It is intentionally not a generic SaaS dashboard.

**Fictional demo data. No affiliation with any bank.**
