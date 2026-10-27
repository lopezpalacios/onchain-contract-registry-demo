# FireFly under Kaleido — deployment integration logic

**Scope:** how a pre-chain registration in the registry becomes an on-chain deployment through a FireFly supernode running on the Kaleido digital-asset platform, and how the registry links the result back to the same request.

This document is implementation guidance, not vendor configuration. Validate the exact FireFly/Kaleido APIs and signing model against the installed versions.

---

## 1. Components and responsibilities

| Component | Responsibility | Does not do |
|---|---|---|
| **Registry** | Pre-chain record, template linkage, risk tier, evidence, approvals, readiness, on-chain reconciliation | Hold keys, submit transactions, replace FireFly |
| **FireFly supernode** | Contract manager, FFI/ABI, deployment/invocation APIs, event listeners, transaction tracking | Decide whether the bank may deploy |
| **FireFly EthConnect / connector** | JSON-RPC submission, nonce management, receipts, event streaming | Replace Kaleido signing policy |
| **Kaleido** | Managed chain, permissioning, node operations, KMS/HSM-backed signing identities, audit | Decide business/compliance approval |
| **Besu / Ethereum** | Execution and final state | Be the system of record for ownership/approvals |
| **Sourcify / Blockscout** | Source verification and explorer evidence | Approve deployment |

The control boundary is:

```text
Developer + business division
        │  onboarding answers
        ▼
Registry ── risk, gates, evidence, template ──► READY / BLOCKED
        │  signed deployment manifest + request ID
        ▼
Deployment service / policy adapter
        │  only if READY
        ▼
FireFly contract manager ──► EthConnect ──► Kaleido signing identity ──► chain
        │                                      │
        │  deployment request/response         │  tx hash, receipt, events
        ▼                                      ▼
Registry sync worker ◄──────────── on-chain code hash / proxy / block
        │
        ▼
Link: deployment_request.id ↔ contract_instance (address, tx, runtime hash)
```

**FireFly must not be allowed to deploy directly from an arbitrary API call.** The deployment service should call the registry/readiness check (or a policy engine such as OPA) and include the returned `manifest_hash` and `request_id` in the FireFly request. That is what makes the registry a control plane rather than a dashboard.

---

## 2. End-to-end sequence

### Step 1 — Onboarding (pre-chain)

The developer/business division answers:

- contract name and purpose;
- code source (new template, approved template with parameters, modified template, third-party/OSS);
- division and accountable business owner;
- chain and environment;
- internal/external/both user impact;
- risk tier (or auto-recommend);
- deployment authority (FireFly under Kaleido);
- evidence available today;
- target window and notes.

The registry creates:

- a `template` record if the code is new/modified/third-party (status `draft`);
- a `deployment_request` with `status='in_review'`;
- pending `signoff` gates from `approval_policy` for the risk tier;
- pending template gates if a new template;
- `config_hash`, `manifest_hash`, `salt`, `evidence_json`;
- `deployment_platform='Kaleido FireFly'` and a `signing_identity_id`;
- an audit-log entry.

No address, transaction or runtime hash exists yet.

### Step 2 — Approvals and evidence

The gates run in order. The final deployment approval is blocked if:

- the template is not approved;
- an independent audit is missing/expired;
- a blocking gate is rejected;
- template gates are incomplete;
- evidence is missing (depending on policy).

The evidence list is the agenda for Compliance, Legal, Risk, Security, DPO, Finance and the CAB. The registry shows what is missing rather than pretending it exists.

### Step 3 — Ready and signed manifest

When the request is `Ready`, the registry produces a canonical deployment manifest:

```json
{
  "request_id": "DR-2026-0064",
  "template_id": "tpl-cmtat-300",
  "template_runtime_hash": "0x…",
  "config_hash": "0x…",
  "manifest_hash": "0x…",
  "chain_id": "ch-besu-uat",
  "environment": "UAT",
  "deployment_platform": "Kaleido FireFly",
  "signing_identity": "si-besu-uat-service",
  "approval_bundle_hash": "0x…",
  "created_at": "2026-10-27T…Z"
}
```

Store the manifest in the document store, hash it, and anchor the hash if required. FireFly/Kaleido should receive the hash and request ID, not an unstructured PDF.

### Step 4 — Submit through FireFly

The deployment service calls the FireFly contract-manager API with:

- FFI/ABI name and version;
- constructor/initializer parameters;
- from/signing identity (Kaleido-managed);
- idempotency key = `request_id`;
- `manifest_hash`;
- chain/network namespace;
- optional gas/nonce policy.

FireFly/EthConnect submits through the Kaleido-managed signing identity. Kaleido permissioning must allow only the deployment service/factory identity to deploy on that network.

### Step 5 — Capture the receipt

FireFly returns a transaction ID/hash. The registry records:

- `deployment_tx`;
- `block_number`;
- `contractAddress`;
- status and revert reason if failed;
- FireFly operation ID and Kaleido transaction reference;
- raw receipt hash/evidence.

Do not mark the request `deployed` until the transaction is final and the code is verified.

### Step 6 — Link the on-chain instance

The registry sync worker:

1. reads `eth_getCode` at the address;
2. computes the runtime hash;
3. reads EIP-1967 implementation/admin/beacon slots and EIP-1167 clone prefix;
4. matches the runtime/init-code hash to the approved template;
5. checks the deployment transaction/block/finality;
6. verifies source via Sourcify/Blockscout or a reproducible build;
7. creates/updates the `contract_instance` with `deployment_request_id = request_id`;
8. sets `link_state = linked_match` or `linked_mismatch`;
9. links implementation/supporting records and factory events;
10. updates `status='deployed'` / `active` according to the operating model.

The same request ID is the join key. The UI shows the request and the deployed address side by side.

### Step 7 — Operate

- FireFly event listeners stream contract events to the registry/SIEM.
- The registry monitors admin/role/upgrade/pause events.
- Upgrade/parameter changes create a new `change_request`, not a new template silently.
- Evidence expiry and reserve reconciliation remain visible in the Council view.

---

## 3. Field mapping

| Registry field | Source |
|---|---|
| `deployment_request.id` | Registry-generated; passed to FireFly as idempotency key |
| `deployment_platform` | `Kaleido FireFly` |
| `signing_identity_id` | Kaleido-managed HSM/KMS identity or FireFly signer |
| `deployment_tx` | FireFly/EthConnect operation / chain transaction hash |
| `contract_instance.address` | FireFly receipt `contractAddress` |
| `contract_instance.block_number` | Receipt block |
| `contract_instance.runtime_code_hash` | `keccak256(eth_getCode)` |
| `template.runtime_code_hash` | Compiled/approved template hash |
| `contract_instance.proxy_type` | EIP-1967/EIP-1167 detection |
| `contract_instance.verification_*` | Sourcify/Blockscout/reproducible build |
| `onchain_event.*` | FireFly event listener / `eth_getLogs` |
| `document.manifest` | Signed deployment manifest |
| `audit_log` | Registry + FireFly/Kaleido operation references |

---

## 4. Failure, retry and control logic

| Scenario | Registry behaviour |
|---|---|
| FireFly API call fails before submission | Keep request `approved`, record failed attempt, do not create an address; retry idempotently |
| Transaction reverts | Keep request `approved`/`failed`, record revert, alert; do not mark deployed |
| Duplicate submission | Idempotency key `request_id`; detect duplicate address/tx; quarantine second deployment |
| FireFly returns an address that does not match template hash | `linked_mismatch`; quarantine, alert, incident |
| Reorg/finality | Wait for finality; store block hash; re-check; handle reorg |
| Wrong signer / non-allowlisted identity | Kaleido permissioning rejects; registry alert; no bypass |
| Deployment outside FireFly | Sync discovers unknown contract; `disc-*` queue; incident |
| Upgrade | New `change_request` with implementation hash, timelock proof and storage layout; link new implementation |
| Pause/incident | FireFly/registry event + playbook; record authority and regulatory reporting decision |

---

## 5. Security controls

- FireFly API behind OIDC/mTLS; not exposed to the internet.
- Kaleido signing identity is HSM/KMS-backed, not an exported private key.
- Separate UAT and production namespaces, identities and permissioning.
- Deployment service is the only identity allowed to call the contract-manager deploy endpoint for production.
- Manifest/request ID required in FireFly metadata; reject calls without it.
- FireFly/Kaleido audit logs retained and linked to registry `audit_log`.
- FireFly event listener credentials rotated; no secrets in FFI/ABI or manifests.
- Monitor for deployments by any other identity (shadow deployment).
- The registry's `/api/onboarding` is a demo endpoint; production must bind it to the developer's IdP identity and the business owner's approval.

---

## 6. What the demo does and does not do

**Does:**

- creates a pre-chain `deployment_request` from the onboarding wizard;
- computes risk and gate count;
- records missing evidence;
- sets `deployment_platform='Kaleido FireFly'` and a signing identity;
- links an existing request to a deployed instance in the Registration view;
- verifies template vs runtime hash and shows pre-chain vs linked states.

**Does not:**

- call a real FireFly/Kaleido API;
- sign or submit a transaction;
- read live Besu privacy groups;
- verify source via Sourcify/Blockscout;
- provide production auth or WORM storage.

The integration boundary is deliberately explicit: the registry is the control plane; FireFly/Kaleido is the execution and custody layer; the chain is evidence.
