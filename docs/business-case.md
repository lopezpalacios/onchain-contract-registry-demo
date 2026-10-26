# Business Case — Smart Contract Inventory & Control Registry

**Status:** illustrative decision support, not a forecast or a substitute for Finance/Risk approval.  
**Scope:** first release focused on the digital-assets / tokenized-gold estate, EVM chains (permissioned Besu + public Ethereum-compatible), with a platform path to other divisions.

---

## 1. The case in one page

The registry is **not primarily a cost-saving tool**. It is a **control and acceleration platform** for a bank that is putting legal rights, client money and reserve-backed assets on-chain.

The value comes from four places:

1. **Audit and assurance reuse** — approve a template once, deploy it many times, and reuse the audit/evidence instead of re-auditing every instance.
2. **Faster, safer launches** — a repeatable golden path reduces the time from business approval to production and removes spreadsheet/explorer archaeology.
3. **Risk and regulatory readiness** — a complete, evidence-linked register for DORA, MiCA, Swiss DLT/FINMA, Basel and internal audit; faster incident response; fewer shadow deployments.
4. **Revenue enablement** — more tokenized products can launch per year because the control path is reusable, not bespoke.

The honest conclusion from the model below:

- **Efficiency-only** (audit savings + manual effort + productivity) does **not** pay back a €1.4m build at a €380k run cost. It is close to break-even and has negative NPV.
- **Base case** (efficiency + risk reduction + a conservative, attributable revenue uplift) pays back in ~2.6 years with positive 5-year NPV.
- **Upside** (scale to more divisions/products) pays back in ~1.3 years.

That is the real argument: fund it as **risk/regulatory infrastructure with a revenue-enablement upside**, not as a headcount-reduction project. If the bank only wants a catalogue, buy/integrate a lighter tool; if it wants a control plane for tokenized assets, build the registry.

---

## 2. Cost of inaction

| Failure mode | Consequence | Registry mitigation |
|---|---|---|
| Template → deployment link is a spreadsheet | Audit cannot prove which code is live; duplicate audits; wrong owner in an incident | Canonical template/instance model, hashes, proxy links, evidence |
| Shadow deployment on a permissioned network | Unapproved code touches client assets; regulatory breach | Besu sync, deployer allowlist, unknown queue, quarantine, incident |
| Stale audit/legal/proof-of-reserve | Product continues on expired assurance; prospectus/reserve breach | Attestation expiry, readiness blocking, alerts, renewal workflow |
| No business sign-off evidence | Personal accountability unclear; audit finding; weak DORA evidence | Risk-tiered gates, role/scope, SoD, evidence hashes, immutable log |
| Public/private double count | Reserve appears over-collateralised or supply is misstated | Representation + reserve pool + `counts_toward_reserve` reconciliation |
| Incident without dependency map | Slow containment; wrong Safe/timelock/admin contacted | Links to rule engine, identity, oracle, Safe, timelock, reserve, docs |
| Key-person dependency | Departure or leave date breaks access/ownership | Role assignments, named owners, delegation, leaver workflow |
| Regulatory request takes weeks | DORA/MiCA/FINMA response late; remediation cost | One-click export, evidence bundle, audit trail |

A single material incident, unresolved audit finding or delayed regulatory response can exceed the annual run cost. That is the risk framing, not a fictitious “millions saved” claim.

---

## 3. Value drivers and assumptions

All figures are in CHF/EUR-equivalent and **illustrative**. Replace them with the bank’s actual loaded costs before committee use.

| Driver | Formula | Base assumption | Annual value |
|---|---|---|---|
| Audit reuse | Audits avoided × cost per audit | 2 × 90k | **180k** |
| Deployment productivity | Deployments × days saved × loaded day rate | 25 × 4 × 1.2k | **120k** |
| Manual registry effort | FTE × loaded cost | 1.0 × 160k | **160k** |
| Regulatory/audit efficiency | Response and evidence effort avoided | — | **100k** |
| Risk-adjusted incident reduction | Loss × probability reduction × confidence | 2.0m × 15% × 50% | **150k** |
| Attributed revenue | Incremental product margin × attribution | 1 launch × 400k × 50% | **200k** |
| **Total annual benefit** | | | **910k** |
| Annual run cost | Platform team + infra + support | 3 FTE + tooling | **380k** |
| **Annual net** | | | **530k** |
| Build cost | 6–8 FTE for ~9 months + integration/legal | — | **1.4m** |
| Simple payback | Build / annual net | | **2.6 years** |
| 5-year NPV @ 10% | −build + Σ net/(1+r)^t | | **+609k** |
| 5-year ROI | (benefits − costs) / costs | | **37.9%** |

Run the model yourself:

```bash
python3 scripts/business_case.py
python3 scripts/business_case.py --scenario base --json
python3 scripts/business_case.py --discount-rate 0.12 --years 7
```

---

## 4. Scenarios

| Scenario | Build | Annual benefit | Annual run | Annual net | Payback | 5-year NPV @10% | 5-year ROI |
|---|---:|---:|---:|---:|---:|---:|---:|
| **One-product control pilot** | 350k | 280k | 150k | 130k | 2.7y | +0.14m | +27.3% |
| **Efficiency only** | 1.40m | 450k | 380k | 70k | 20.0y | −1.13m | −31.8% |
| **Base** | 1.40m | 910k | 380k | 530k | 2.6y | +0.61m | +37.9% |
| **Upside** | 1.40m | 1.55m | 450k | 1.10m | 1.3y | +2.77m | +112.3% |

### What the scenarios mean

- **One-product control pilot** is the revised recommendation from the persona council. It is a €350k, one-product, 10–15 template pilot with enforcement and a redemption slice. It pays back in ~2.7 years on control/efficiency benefits alone and produces the baseline needed for a scale decision. It is not a substitute for the full platform case.
- **Efficiency only** is a warning: do not sell the platform on audit savings and headcount alone. A €1.4m build with a €380k run needs risk or revenue value to clear a bank hurdle rate.
- **Base** assumes one attributable incremental launch per year and a conservative 50% attribution. If the bank cannot attribute revenue, use the control case and fund it from risk/compliance budget.
- **Upside** assumes reuse across more divisions/products (5+ launches/year, 3+ divisions, 30+ deployments/year). The platform becomes cheaper per deployment as volume grows.

### Finance challenge to the original case

A Finance reviewer pushed back on the original base case for three reasons:

1. Only the audit-reuse benefit is hard cash; the FTE avoidance contradicts a “no headcount reduction” promise, and the revenue/incident benefits are soft or attributed.
2. A one-year ramp materially lowers NPV; the original 25 deployments/year is higher than the demo’s 16 logical contracts.
3. The cost model excluded HSM hardware, gas, custody/audit providers and external counsel.

The revised ask is therefore a **€350k pilot**, not €1.4m. The scale case remains available, but it must be earned with pilot evidence: coverage, enforcement, evidence quality and a redemption baseline.

A separate **control-only** framing should be used if Finance will not accept revenue attribution: value the register as a DORA/audit/incident-response control, compare against the cost of a single material finding or incident, and fund it from the control budget. Do not double-count the same risk reduction in both the business and control cases.

---

## 5. Cost model

The table below is the **€1.4m scale case (Phase 2)**. The recommended **€350k pilot** assumes 3–4 FTE for six months, limited integration, one product and no WORM/production hardening. Its economics are in `scripts/business_case.py` and the scenario table above.

| Cost line | Year 1 | Annual run | Notes |
|---|---:|---:|---|
| Product/engineering | 700k | 220k | 5–6 FTE build, 2 FTE run |
| Integration (Besu/CMDB/GRC/SIEM) | 250k | 60k | RPC, ServiceNow, Archer/Splunk |
| Security/architecture review | 120k | 30k | Threat model, pen test, key custody |
| Legal/compliance/regulatory | 150k | 30k | DORA/MiCA/tokenization review |
| Infrastructure | 50k | 40k | Postgres, object store, WORM, monitoring |
| Training/change | 80k | 0 | Taxonomy, workflow, data stewardship |
| Contingency 10% | 50k | 0 | |
| **Total** | **1.4m** | **380k** | |

Not included: chain gas, HSM hardware, Safe signer operations, custody/audit providers, external counsel, and product-specific legal work. Those should be charged to the product, not the registry platform.

### Funding options

1. **Central control budget** — best fit if the driver is DORA/audit/incident response.
2. **Shared platform with chargeback** — per deployment, per template, per chain, or per division; aligns cost with reuse.
3. **Product-funded pilot** — digital gold pays for the first release; platform team reuses it for the next product.
4. **Regulatory programme** — fold into DORA/MiCA/tokenization remediation budgets rather than a standalone IT case.

Recommendation: fund Phase 1 centrally as a **control platform**, then move to a **hybrid chargeback** model once there are 3+ products/divisions. This avoids a “tax on the first product” and keeps the platform accountable for reuse.

---

## 6. Benefits by stakeholder

| Stakeholder | What they get |
|---|---|
| **CIO / COO** | One inventory, lower unit cost per deployment, fewer bespoke launches, clear ownership |
| **CISO** | Key custody and admin-role visibility, upgrade/role monitoring, shadow-deployment detection, incident dependency map |
| **Business / Digital Assets** | Faster launches, reusable templates, fewer manual approvals, clear product ownership |
| **Compliance** | Transfer restrictions, rule-engine changes, identity/claim registries, DORA/MiCA evidence |
| **Legal** | Terms/prospectus/legal opinions linked to the address; jurisdiction and legal entity |
| **Operational Risk** | Risk-tiered approvals, control tests, exceptions, incidents, audit trail |
| **Internal Audit** | Independent read-only evidence, complete sign-off history, coverage and exception reporting |
| **Finance / Treasury** | Reserve reconciliation, supply by pool, cost per deployment, capital/risk data |
| **Software Inventory / CMDB** | Template → CI mapping, lifecycle, vendor/OSS dependency, retirement |

---

## 7. KPIs and success measures

| KPI | Definition | Target by end of Phase 2 |
|---|---|---|
| **Registry coverage** | registered logical contracts / (registered + unknown) | ≥ 95% |
| **Template reuse** | deployments from approved templates / total deployments | ≥ 80% |
| **Approval completeness** | high/critical deployments with all blocking gates approved before deployment | 100% |
| **Evidence freshness** | in-scope templates with valid audit/attestation | ≥ 95% |
| **Shadow deployments** | unapproved production deployments per quarter | 0 |
| **Time-to-deploy** | median approved-request → production | −30–50% |
| **Audit reuse** | deployments using an already-audited template without duplicate audit | ≥ 60% |
| **Incident MTTR** | time to identify owner, authority and dependencies | −50% |
| **Exception closure** | exceptions closed by due date | ≥ 90% |
| **Cost per deployment** | annual run cost / deployments per year | declining with volume |

The registry should publish these as a monthly control dashboard. The demo’s **Overview** and **Controls** views are a prototype of that dashboard.

---

## 8. Regulatory mapping (starting point, not legal advice)

| Regulation / standard | What it expects | Registry contribution |
|---|---|---|
| **DORA** (EU, applicable 2025) | ICT risk management, register of information for ICT third-party arrangements, incident reporting, operational resilience, testing | Contract/CI inventory, criticality, third-party links, incident register, evidence, exit/continuity fields, export |
| **MiCA** (EU) | Crypto-asset issuer/ART/EMT requirements, reserve assets, white paper, governance, custody | Token/reserve pool, proof of reserve, custody, terms, transfer restrictions, governance |
| **Swiss DLT Act / FINMA** | Ledger-based securities, custody, tokenization, DLT trading facility | Legal entity, jurisdiction, legal opinion, custody, transfer restrictions, register |
| **Basel SCO60** (crypto-asset exposures) | Classification, capital treatment, risk management | Asset classification, exposure, reserve, chain/network, risk tier |
| **AML / KYC / sanctions** | Investor eligibility, sanctions screening, travel rule | Identity registry, claim topics, trusted issuers, sanctions rules, audit trail |
| **GDPR / data protection** | Lawful processing, minimisation, retention, no unnecessary on-chain PII | DPO gate for critical deployments, privacy group, off-chain PII, hashes only |
| **SOX / internal control** | Change control, segregation of duties, evidence | Gate order, SoD, change requests, immutable audit log |
| **EEA EthTrust** | Smart contract security assurance levels | Template attestation, level, scope, expiry |

The registry does not make a product compliant. It makes compliance **evidenced, repeatable and auditable**.

---

## 9. Risks to the business case

| Risk | Impact | Mitigation |
|---|---|---|
| Low adoption / shadow spreadsheets | Benefits evaporate; two sources of truth | Make registry the only path to deployment approval; CMDB/GRC integration; executive sponsor; data stewards |
| Scope creep into an explorer/CMDB | Cost blowout | Integrate Sourcify/Blockscout/ServiceNow; do not rebuild them |
| Weak enforcement | Registry records but does not control | HSM/CI/Besu permissioning; only approved manifests can deploy |
| Data quality | Wrong coverage/owners; audit findings | CAIP-10/EIP-55, canonical hashes, dedupe, validation, ownership SLA |
| Vendor/OSS risk | Licence or maintainer issue; supply-chain compromise | SBOM, licence review, pinning, internal fork/exit plan |
| Regulatory change | Model becomes stale | Quarterly taxonomy/policy review; configurable policy-as-data |
| Key-person dependency | Platform stalls | Documented operating model, runbooks, 2 FTE minimum, training |
| Revenue attribution challenged | Base case collapses to control case | Present control-only case; do not double-count; use Finance-approved attribution |
| Over-engineering for EVM-only | Non-EVM later requires rewrite | Chain-agnostic core + adapter; `chain_id`/CAIP-2, no EVM assumptions in business fields |

---

## 10. Decision ask

Approve a **€350k one-product control pilot** with the following guardrails:

1. **Scope:** digital gold + one permissioned Besu network + one public network; 10–15 templates; 10–15 deployments; one redemption journey.
2. **Budget:** €350k build / €150k annual run for the pilot; the €1.4m scale case is a separate Phase 2 decision.
3. **Success gates (6–9 months):**
   - 100% of in-scope gold contracts registered and reconciled;
   - 100% of high/critical deployments with complete sign-offs before deployment;
   - zero unapproved production deployments;
   - evidence gaps reduced to an agreed threshold (start from the 141 placeholder gates);
   - audit walkthrough passes with evidence export;
   - DORA/MiCA evidence export tested with Compliance;
   - redemption TAT baseline established.
4. **Stop/go:** if coverage, adoption and evidence quality gates are not met, stop before scaling to other divisions or requesting the €1.4m build.

### What would make the case stronger

- Replace all illustrative inputs with **actual** audit fees, loaded FTE costs, deployment lead times and incident scenarios.
- Measure the baseline for 8–12 weeks before build: number of contracts, spreadsheet/explorer effort, audit duplication, time-to-deploy, unknown deployments.
- Run a **shadow-deployment tabletop** with Security/Compliance: how long would it take today to identify owner, authority and dependencies?
- Quantify one real regulatory/audit finding or near-miss and use it as the risk anchor.
- Get Finance to agree the revenue attribution method (or drop revenue and use the control case).
- Do not promise headcount reduction; promise **risk reduction, speed and evidence**.
- Run the pstack-style council review before the committee: see `docs/persona-review.md` and `PSTACK.md`.
- Treat the 141 placeholder approval evidence gaps as the first remediation item, not a documentation detail.

---

## 11. Sources / benchmarks

- The demo’s base case and calculator: `scripts/business_case.py`.
- CMTAT production references and audit notes: <https://github.com/CMTA/CMTAT>.
- EEA EthTrust: <https://entethalliance.org/specs/ethtrust-sl/>.
- DORA: <https://www.eiopa.europa.eu/digital-operational-resilience-act-dora_en>.
- MiCA: <https://www.esma.europa.eu/esmas-activities/digital-finance-and-innovation/markets-crypto-assets-regulation-mica>.
- FINMA DLT: <https://www.finma.ch/en/authorisation/fintech-and-dlt/>.
- Basel SCO60: <https://www.bis.org/bcbs/publ/d545.htm>.
- LBMA Good Delivery: <https://www.lbma.org.uk/good-delivery>.

*All monetary figures are illustrative assumptions for discussion, not a bank forecast. Legal/regulatory mapping must be validated by Compliance, Legal and Internal Audit.*
