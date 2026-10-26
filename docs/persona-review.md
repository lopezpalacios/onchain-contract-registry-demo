# Persona Review — Banking Compliance & Control Council

**Review cycle:** October 2026  
**Objects:** tokenized-gold registry, permissioned Besu + Ethereum deployments, approval workflow, evidence, reserve, business case.  
**Method:** pstack-style independent role review, then cross-review and synthesis.  
**Verdict:** the registry is a useful control-plane prototype, but it was not yet credible as a compliance or audit system. Several findings were fixed in this iteration; the remaining ones are visible in the **Council** view and should be treated as gate items, not as documentation debt.

---

## 1. What each role concluded

### Business Owner / Product

The product solves a real problem: it gives a single place to answer “what is live, who owns it, what did we approve, and what is the client promise?” The tokenized-gold scenario is a good lighthouse because it exercises legal title, reserve, transfer restrictions and public/private representations.

But the business case was oversold. The original €1.4m build with a 50% revenue attribution did not survive a Finance challenge. The pilot should be smaller and prove **enforcement, coverage and redemption**, not just catalogue screens. The demo now includes redemption fields and a smaller pilot scenario in the business-case model.

### Compliance / AML & Sanctions

The approval workflow looked strong on paper but was not evidence. The biggest issues were:

- approvals were asserted by a browser-supplied actor, not an IdP;
- sanctions and travel-rule checks were fields, not screening records;
- the public token’s transfer restrictions were not linked to the rule engine/identity registry;
- the country-rule admin was an EOA controlled by the same compliance officer who approved the gate;
- no complaints/redress path.

This review added **compliance profiles** for AML risk, client eligibility, sanctions, travel rule, distribution countries, complaints and retention; it added a **four-eyes** check; it surfaced **evidence gaps**. It did not pretend that the missing screening evidence is present.

### Legal / Regulatory

The register did not prove **legal title**, **insolvency remoteness**, **token classification**, **prospectus/terms**, or **cross-border distribution**. The public and ledger tokens shared an ISIN/symbol but used separate pools, which is a fungibility and disclosure question. The legal gate had no signed document hash.

This review added:

- legal structure, holder claim, segregation basis, insolvency remoteness, custody agreement and legal title fields;
- MiCA/regulatory classification, instrument ID and fungibility group;
- DORA and ICT third-party references;
- evidence-gap reporting that shows the legal gate is not yet audit-ready.

### Operational Risk / Internal Audit

The control design was good, but the evidence was not. Specific findings:

- the original 84 sign-offs had only a handful of documents; the registry now has 166 gates, with 141 evidence gaps still visible;
- all gates of a request stamped at the same timestamp, which implies bulk backfill rather than sequential review;
- `audit_log` was mutable;
- minimal approvals were always 1, so no four-eyes;
- critical templates `tpl-dvp-100` and `tpl-collateral-100` were approved with zero template gates;
- exceptions had no expiry and were accepted by the same person who owned the control;
- DORA evidence covered only one public token.

This review added complete template gates for every approved high/critical template, a four-eyes trigger, append-only audit-log triggers, an evidence-gap view, reserve reconciliation, and an ICT third-party register.

### CISO / Smart Contract Security

The registry recorded addresses, not **deployer identity**. It also recorded upgrades without a prior implementation record, timelock delay proof or storage-layout evidence. The country-rule admin was an EOA; `ci-safe-besu` was listed as its own deployer; source verification on Besu was an “internal manifest” claim.

This review added:

- `signing_identity` with HSM/CI/multisig/timelock type, provider, owner, allowlist and validity;
- a deployer-risk view that flags the legacy non-allowlisted deployer;
- signer identity in the contract UI and compliance tab;
- a visible `auth_method` showing that the demo approval is not production evidence.

Still open: upgrade history, timelock delay verification, live source verification, and privacy-group-aware Besu discovery.

### DPO / Privacy

The biggest privacy risk was not a missing field; it was the assumption that a public token can publish legal terms, supply and holder activity without a DPIA. The privacy group was a label, not a member list. Free-text approval comments could carry personal data into an audit log.

This review added:

- DPIA reference, DPO assessment, on-chain PII risk and privacy-group membership fields;
- DORA/ICT third-party links;
- Council findings for DPIA and privacy-group evidence;
- a visible warning that public-chain metadata is permanent.

Still open: DSAR/retention workflow, comment minimisation, hash-only anchoring, and privacy-group transaction hashes.

### Finance / Treasury / Reserve

The reserve story did not reconcile. The public snapshot claimed 8 bars / 93,425g but listed 4 bars / 50,000g; the ledger claimed 3 bars / 37,500g vs 32,825g. Coverage was calculated from free-entered snapshot values, not from the bar list and on-chain supply.

This review **fixed the bar list** to sum to the snapshots, added `v_reserve_reconciliation`, and now shows supply delta, bar delta and a reconciled flag. It also added a service/reserve reconciliation section to the Council view.

Still open: reading `totalSupply()` from chain in the reconciliation job, full bar-list hash publication, and Finance-approved revenue attribution.

### Regulator / External Audit

The register is readable, but an external auditor cannot yet rely on it: no IdP evidence, no document hashes, no WORM, no formal DORA export, no complaint/redress record, and no incident for the unknown cloned token. The Council view now makes those gaps explicit instead of hiding them.

---

## 2. Top findings and disposition

| Severity | Finding | Role | Disposition |
|---|---|---|---|
| Critical | Approvals are self-asserted; no IdP/MFA | Compliance / Risk | **Open** — visible in Council; production must bind to OIDC/MFA |
| Critical | Legal gate has no signed document/hash | Legal | **Open** — evidence-gap view |
| High | Public token restrictions not linked to Besu rule engine/identity | Compliance | **Open** — needs mainnet link and transfer test |
| High | Legal title / insolvency remoteness not recorded | Legal | **Open** — compliance profile records the gap |
| High | DORA scope covers only one token | Risk | **Open** — ICT register added, formal DORA export remains |
| High | Deployer identity/key custody not modelled | Security | **Remediated** — signing identity and allowlist |
| High | Proxy upgrade governance not proven | Security | **Open** — upgrade history still needed |
| High | No DPIA for public gold token | DPO | **Open** — DPIA reference recorded |
| High | Privacy-group membership not recorded | DPO | **Open** — member fields added, evidence still needed |
| High | Reserve bars did not reconcile | Finance | **Remediated** — bar list + reconciliation view |
| High | Critical templates had no template gates | Risk | **Remediated** — complete gate sets |
| High | Approval evidence is placeholder | Risk | **Open** — evidence-gap count surfaced |
| Medium | Redemption journey not represented | Business | **Open** — fields added, queue not built |
| Medium | Revenue attribution not Finance-approved | Finance | **Open** — pilot scenario added; attribution still challengeable |
| Medium | No complaints/redress record | Compliance | **Open** — fields added, workflow not built |
| Medium | Unknown clone not incident-linked | Security | **Open** — incident link still needed |
| Medium | Retention/DSAR incomplete | DPO | **Open** |
| Low | One person can hold two blocking roles | Risk | **Remediated** — four-eyes trigger + API check |
| High | Public/ledger tokens share ISIN with separate pools | Legal | **Open** — instrument/fungibility fields added |
| High | Sanctions/travel rule evidence is asserted | Compliance | **Open** — screening records still needed |

The live list is in `v_persona_findings` and the **Council** view.

---

## 3. What changed in the demo because of this review

1. **Council view** — eight personas, open findings, owners, due dates, decision rights.
2. **Compliance profile** — regulatory classification, MiCA, legal title, holder claim, segregation, insolvency, AML, sanctions, travel rule, distribution, DPIA, DORA, redemption, complaints, retention, tax.
3. **Signing identity** — HSM/CI/multisig/timelock, allowlist, owner, validity; visible in contract detail.
4. **Four-eyes** — database trigger and API check; one person cannot approve two blocking gates on the same object.
5. **Template gates** — every approved high/critical template has a complete gate set; readiness blocks pending template gates.
6. **Reserve reconciliation** — bar list now sums to the snapshot; supply/bar deltas and reconciled flag.
7. **Evidence gaps** — 141 approved gates with placeholder/missing evidence are visible in the Council view.
8. **ICT third parties** — Chainlink, Besu consortium, custodian, auditor and private cloud linked to instances.
9. **Append-only audit log** — database triggers reject UPDATE/DELETE.
10. **Pilot economics** — business-case model now includes a €350k one-product control pilot alongside the €1.4m scale case.

---

## 4. What the council still would not approve

The demo should **not** be presented as production-ready or as evidence of compliance. The following are gate items:

- IdP/MFA and server-side identity binding;
- document hashes and document links for every approved gate;
- legal title, custody agreement and insolvency opinion;
- sanctions screening records with list version and disposition;
- travel-rule payloads and VASP diligence;
- DPIA, ROPA, privacy-group member list and transaction hashes;
- DORA register-of-information export and incident reporting;
- upgrade history, timelock proof and storage-layout evidence;
- live source verification and independent rebuild;
- redemption request queue, TAT and complaint/redress workflow;
- WORM/hash-chained audit storage and legal hold.

That is the honest boundary between a good demo and a control the bank can rely on.

---

## 5. Business verdict

The business reviewer’s original verdict was:

> **Yes** to a €300–500k one-product control pilot with enforcement and a redemption slice.  
> **No** to €1.4m on the original business case.

This iteration keeps that verdict. The revised recommendation is a **€350k pilot**, one product (tokenized gold), one permissioned network plus one public network, 10–15 templates, with explicit exit criteria:

- 100% of in-scope contracts registered and reconciled;
- all high/critical deployments gated before production;
- zero unapproved production deployments;
- evidence gaps reduced to an agreed threshold;
- one regulator/audit walkthrough completed;
- redemption TAT baseline established.

Only then should the bank scale to €1.4m and multiple divisions.
