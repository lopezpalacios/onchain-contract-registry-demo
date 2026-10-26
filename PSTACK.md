# pstack — Banking Compliance & Control Review Council

This project uses a **pstack-style review** for a smart contract registry. It is not a model configuration file; it is the review protocol and role stack that forces the product to be challenged by the people who have to approve, operate and audit it.

The point is not to collect generic comments. Each role has a **mandate**, **decision rights**, **questions** and **evidence asks**, and each finding becomes an owned, dated item in the registry.

---

## 1. The eight roles

| Role | Mandate | Decision rights | Core questions |
|---|---|---|---|
| **Business Owner / Product** | Commercial outcome, client proposition, pricing, adoption, redemption journey | Accountable for launch and client journey; cannot self-approve risk/compliance | Who is the client? What is the redemption promise? What is the unit economics? What happens when the product is paused? |
| **Compliance / AML & Sanctions** | Eligibility, KYC/AML, sanctions, travel rule, transfer restrictions, complaints | Can block or condition; must evidence screening and eligibility | Who can hold? How are sanctions re-screened? What is the travel-rule path? How is a refused client handled? |
| **Legal / Regulatory** | Legal title, token classification, prospectus/terms, custody, cross-border, DORA/MiCA/FINMA | Can block or condition; signs legal opinion and terms | Is the token a security/ART/EMT/deposit? Who owns the gold? Is it segregated and insolvency-remote? Which countries? |
| **Operational Risk / Internal Audit** | Control design, evidence, exceptions, incidents, DORA register, audit readiness | Can block or condition; accepts residual risk within mandate | Can the approval be reperformed? Is the audit trail WORM? Are exceptions time-bound? Is the DORA register complete? |
| **CISO / Smart Contract Security** | Key custody, deployer identity, upgrades, source verification, monitoring, incident response | Can block or condition; can invoke emergency pause | Who can deploy? Which HSM/CI identity? Is the proxy upgrade delayed and evidenced? Is source verified? |
| **DPO / Privacy** | DPIA, PII boundaries, privacy groups, retention, DSAR, cross-border data | Can block or condition; must approve public-chain and identity data | What is on-chain? Can it be erased? Who is in the privacy group? Is there a DPIA? |
| **Finance / Treasury / Reserve** | Reserve reconciliation, accounting, capital, tax, cost and chargeback | Can block or condition; signs reserve and accounting treatment | Do bars sum to the snapshot? Does supply read on-chain? Is the reserve audited? What is the capital/tax treatment? |
| **Regulator / External Audit** | Read-only challenge of evidence, register completeness, incident reporting, consumer outcomes | No approval right; can require remediation/escalation | Show me the register, the approvals, the evidence and the incident history. Can I reproduce the numbers? |

---

## 2. Review protocol

1. **Independent read.** Each persona reads the register, the schema, the UI and the business case without seeing the other personas' findings.
2. **Evidence challenge.** Each finding must name a specific record, field, query or UI flow. "Best practice" is not a finding.
3. **Severity and ownership.** Critical/high findings get an accountable owner, due date and evidence artifact.
4. **Cross-review.** Compliance and Legal challenge each other on transfer restrictions and title; Risk and Security challenge the evidence; DPO challenges public-chain data; Finance challenges reserve and business case.
5. **Decision.** The council does not "approve the product"; it decides whether the **control evidence** is sufficient for the next gate.
6. **Record.** Findings live in `persona_finding`; the UI is the **Council** view. A finding can be `open`, `accepted`, `remediated`, `closed` or `risk_accepted`.
7. **Re-review.** Any material change (new chain, new legal entity, upgrade, new reserve pool, new third party) reopens the relevant persona review.

---

## 3. What the council changed in this build

| Finding | Change made |
|---|---|
| Deployer identity was not modelled | Added `signing_identity`, linked to every instance, with HSM/CI/multisig/timelock type, allowlist and evidence. Added a deployer-risk view. |
| One person could approve multiple gates | Added a database trigger and API check: one person may approve only one blocking gate per object. |
| Critical templates had no template gates | Generated complete template gates for every approved high/critical template; readiness checks pending template gates. |
| Reserve bars did not reconcile to snapshots | Fixed the bar list to sum to 93,425g and 32,825g; added `v_reserve_reconciliation` and tests. |
| No compliance profile | Added `compliance_profile` with classification, legal title, AML, sanctions, travel rule, DPIA, DORA, redemption, complaints, retention and tax fields. |
| No ICT third-party view | Added `ict_third_party` and `instance_ict`, linked to chain, oracle, custody, audit and cloud dependencies. |
| Approval evidence was opaque | Added `v_signoff_evidence_gaps` and a Council KPI showing exactly which approved gates have placeholder or missing evidence. |
| Audit log was mutable | Added database triggers that reject UPDATE and DELETE on `audit_log`. |
| Public/private supply could be confused | Reserve pools, `representation`, `counts_toward_reserve`, supply delta and bar reconciliation are now visible. |

---

## 4. What is still open

The council deliberately leaves these visible rather than hiding them:

- **No IdP / MFA**: the demo uses an actor selector and records `auth_method=demo-actor-selector`. Production must bind to OIDC and MFA.
- **Approval evidence is placeholder**: 141 approved gates still have placeholder `evidence://` URIs and no document hash. The Council view reports this; production should block approval without a document/hash.
- **Legal title / insolvency opinion**: compliance profiles record the gap; legal opinions and custody agreements still need to be attached.
- **Sanctions / travel rule**: fields exist; screening results, list version and VASP payloads are not yet modelled.
- **DPIA / privacy-group membership**: DPIA references exist; full DPIA, ROPA, member lists and transaction hashes are not.
- **DORA register**: ICT third parties are linked, but the formal register-of-information extract and incident notification workflow are still external.
- **Redemption / complaints**: SLA and complaint fields exist, but the request queue, TAT and redress workflow are not built.
- **Source verification**: Sourcify/Blockscout links are modelled; no live verification call is made.
- **WORM**: audit log is append-only in SQLite; production needs WORM/hash-chained storage and legal hold.

---

## 5. How to run the review

In the UI: open **Council**. In SQL:

```sql
SELECT * FROM v_persona_summary ORDER BY sort_order;
SELECT * FROM v_persona_findings WHERE status = 'open' ORDER BY severity;
SELECT * FROM v_compliance_coverage;
SELECT * FROM v_signoff_evidence_gaps;
SELECT * FROM v_ict_coverage;
SELECT * FROM v_reserve_reconciliation;
SELECT * FROM v_deployer_risk;
```

For a committee pack, export the register JSON and include the Council view screenshot plus the open findings and evidence gaps.

---

## 6. Editorial rule

A finding is only closed when the **evidence exists**, not when the product team says it is fixed. The Council view is intentionally uncomfortable: it shows what audit cannot yet rely on.
