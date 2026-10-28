# Platform Guide

This guide uses ASD-STE100 Simplified Technical English. It uses short sentences, active voice, and one term for one idea.

---

## 1. Why a smart contract is a software component

A smart contract is software. It has source code. It has dependencies. It has a build. It has tests. It has bugs. It has an owner. It runs on a computer that other people also use.

A smart contract is not a legal contract. It is code that executes a rule. The legal agreement, the product terms and the code are separate objects. Each object needs its own owner and evidence.

A smart contract has properties that other software does not have all of:

- It can hold and move value.
- A transaction can be irreversible.
- On a public chain, any person can call a public function.
- An upgrade can change behavior after approval.
- An admin key or proxy admin can change the contract.
- Its state and dependencies live outside the repository.

These properties do not remove the need for software controls. They increase the need.

The institution must control:

- the source repository and commit;
- the build and compiler settings;
- the tests and static analysis;
- the independent audit;
- the release and approval;
- the deployed runtime bytecode;
- the proxy admin and upgrade path;
- the incident and patch process.

A repository tag is not enough. It shows what a team intended to release. It does not show what runs at an address.

A block explorer is not enough. It shows what runs at an address. It does not show who approved it, why, or with what evidence.

The registry treats the contract as a software component with a lifecycle. It links the software record to the deployed record.

---

## 2. Why the registry covers pre-chain and on-chain

The registry has two records for one contract. They answer different questions.

The **pre-chain record** answers: **should this contract exist?**

It has the template and version, the product and purpose, the chain and environment, the risk tier, the config hash, the manifest hash, the approval gates, the evidence, and the signing identity. No address exists at this point.

The **on-chain record** answers: **what exists?**

It has the address, the deployment transaction, the block, the runtime code hash, the proxy and implementation, the admin, and the state. The chain does not know who approved the deployment.

The **link** answers: **is the code on chain the code that was approved?**

The link uses the deployment request ID, the template runtime hash, the on-chain runtime hash, the transaction, and the block. If the hashes do not match, the registry shows a mismatch. A mismatch is an incident, not a display error.

| Control question | Record that answers it |
|---|---|
| Is this code approved? | Template with version and runtime hash. |
| Is this deployment allowed? | Pre-chain request with gates and evidence. |
| Is this the code that runs? | On-chain runtime hash. |
| Who can change it? | Proxy admin, roles and signing identity. |
| Is the evidence current? | Evidence with an expiry date. |
| Is it still the same? | Reconciliation against the chain. |

Do not merge these records.

- If you keep only the repository, you control intent but not runtime.
- If you keep only the block explorer, you see runtime but not authority.
- If you keep only a spreadsheet, you have neither integrity nor proof.

This separation is not a workflow preference. It is the separation of decision from fact.

The chain is a runtime, not a register of intent. FireFly and Kaleido are the execution plane. The registry is the control plane. The registry does not sign. It proves what was approved and what was deployed.

The registry does not put approval comments or evidence on the chain. That data is private and large. The chain holds the runtime. The registry holds the decision and the evidence. A hash connects the two records.

---

## 3. What problem the platform fixes

A financial institution has many smart contracts. Teams keep different records. A developer uses a repository. A business team uses a spreadsheet. An auditor uses a block explorer. No person can see the full record.

One failure is common. A team approves a template. A developer deploys it. The address goes into a chat message. Six months later, no person can link the address to the approval. The evidence is lost.

This causes four problems:

1. A person cannot link an approved template to a deployed address.
2. A person cannot see who approved a deployment.
3. A person cannot see if the evidence is current.
4. A person cannot find a contract that was deployed without approval.

The platform gives one controlled record for each contract. The record answers four questions:

| Question | Without the platform | With the platform |
|---|---|---|
| Which code is approved? | A repository and a tag. | A template with a version and a code hash. |
| Who approved this address? | Chat messages and email. | A gate record with a role, a decision, and a date. |
| Is the evidence current? | A shared folder. | Evidence with an owner, a hash, and an expiry date. |
| What runs on chain? | A block explorer. | An instance record with an address and a runtime hash. |

---

## 4. What the platform does

The platform records five objects:

| Object | Meaning |
|---|---|
| **Template** | The approved code. It has a version, a hash, an audit, and an owner. |
| **Deployment request** | The business intent. It has a product, a chain, a risk tier, and a target date. |
| **Approval gate** | One business or control decision. A gate has a role, a decision, a comment, and evidence. |
| **Contract instance** | The on-chain record. It has an address, a transaction, a block, and a code hash. |
| **Evidence** | A document or attestation. It has an owner, a validity date, and a hash. |

The platform links these objects with one key: the **deployment request ID**.

```text
Template
   ↓
Deployment request  ←  approvals + evidence
   ↓
Contract instance   ←  address + transaction + block + code hash
```

The platform shows three states:

- **Pre-chain**: the request exists. No address exists.
- **Linked**: the request has an address. The code hash matches the template.
- **Mismatch**: the request has an address. The code hash does not match the template.

---

## 5. What the platform does not do

- It does not sign a transaction.
- It does not hold a private key.
- It does not replace FireFly.
- It does not replace Kaleido.
- It does not replace the approval system of record.
- It does not make a contract compliant.
- It does not put personal data on a chain.

FireFly submits the deployment. Kaleido signs the transaction and enforces permission. The platform controls the record and the evidence.

---

## 6. How to use the platform

### Step 1 — Open Overview

Open **Overview**.

Read the six measures. Read the approval queue. Read the attention list.

Use this screen to find work that is late, blocked, or missing evidence.

Open **Flow** and select **Play flow** to see the hand-off from template to pre-chain request, gates, FireFly/Kaleido, on-chain instance and reconciliation.

### Step 2 — Start a registration

Open **Onboarding**.

Enter the contract name. Select the purpose. Select the code source.

Select the business division and the business owner.

### Step 3 — Select the deployment target

Select the chain and the environment.

Select the user group:

- internal only;
- external clients;
- both.

Select the risk tier. If you select **Auto**, the platform calculates the minimum tier.

Select **FireFly under Kaleido** as the deployment authority.

### Step 4 — Declare the evidence

Select the evidence that you have today.

The platform does not verify the evidence at this step. It records your declaration.

The platform shows the evidence that is missing.

### Step 5 — Review the record

Read the risk tier, the gate count, and the missing evidence.

If the risk tier is below the policy minimum, the platform stops the request. Select the correct tier.

Select **Create pre-chain registration**.

The platform creates a deployment request. The request has no address. The request has no transaction.

### Step 6 — Approve the gates

Open **Approvals**.

Find the request. Read the gate rail.

The gates run in order. The first gate is the business owner. The last gate is the change advisory board.

For each gate:

1. Select the eligible actor.
2. Read the request and the evidence.
3. Enter a comment.
4. Select **Approve** or **Reject**.

The platform enforces these rules:

- The requester cannot approve.
- One person cannot approve two blocking gates on one object.
- An earlier blocking gate must be approved first.
- A final deployment gate cannot pass if the template or the audit is not ready.

### Step 7 — Deploy with FireFly under Kaleido

When all gates are approved, the request becomes **Ready**.

Use FireFly to submit the signed manifest. Kaleido signs the transaction. Kaleido permissioning allows only the deployment service.

The platform does not submit the transaction.

### Step 8 — Link the on-chain record

Open **Registration**.

The platform shows the request and the on-chain record together.

Check these fields:

- address;
- deployment transaction;
- block number;
- proxy type;
- runtime code hash;
- template runtime code hash;
- verification provider.

If the two hashes match, the link state is **Hash match**.

If the two hashes do not match, the link state is **Hash mismatch**. Stop the process. Open an incident.

### Step 9 — Review the control evidence

Open **Council**.

Read the findings from these roles:

- Business;
- Compliance;
- Legal;
- Operational Risk;
- Security;
- Data Protection;
- Finance;
- Regulator.

Each finding has an owner, a due date, and a recommended action.

Read the **Approval evidence gaps** table. The table shows the gates that have a placeholder or no document hash.

### Step 10 — Monitor the controls

Open **Controls**.

Read the control coverage. Read the exceptions. Read the expiring evidence. Read the incidents.

Do not close an exception without a second approver and an expiry date.

---

## 7. Terms

Use these terms in the user interface and in meetings:

| Term | Use this meaning |
|---|---|
| **Template** | Approved code with a version and a hash. |
| **Deployment request** | Pre-chain record with a product, chain, risk, and gates. |
| **Contract instance** | On-chain record with an address and code hash. |
| **Gate** | One approval decision with a role and evidence. |
| **Evidence** | A document or attestation that supports a decision. |
| **Ready** | All blocking gates are approved and the template is valid. |
| **Linked** | The request has a verified on-chain record. |
| **Mismatch** | The on-chain runtime hash does not match the template. |
| **Control plane** | The registry. It records intent, approval and evidence. It does not sign transactions. |
| **Execution plane** | FireFly, Kaleido and the chain. It submits, signs and runs the contract. |
| **Pre-chain record** | The decision record before an address exists. |
| **On-chain record** | The fact record after deployment. |

Do not use these terms:

- "onboard" as a synonym for deploy;
- "approved" when you mean "declared";
- "verified" when you mean "submitted";
- "live" when you mean "deployed".

---

## 8. Two-minute presentation script

> This is a contract control platform. It does not deploy contracts. It controls the record before and after deployment.
>
> Open Flow and select Play flow. It shows the hand-off from approved template to pre-chain request, gates, FireFly/Kaleido, on-chain instance and reconciliation.
>
> Treat a smart contract as software. It has a source, a build, tests, an audit, an owner, and a runtime. It can hold value. It can be upgraded. It can be called by anyone on a public chain. The controls must cover the software lifecycle and the deployed instance.
>
> The problem is simple. A financial institution can approve a template. A developer can deploy it. But the institution cannot always link the approval to the address.
>
> The platform has four layers. Template. Deployment request. Contract instance. Evidence.
>
> Start at Onboarding. The business division enters the purpose, the chain, the users, and the risk. The platform calculates the gates and shows the missing evidence.
>
> The record is pre-chain. It has no address. It answers: should this contract exist?
>
> The approvers work in order. Business. Compliance. Legal. Risk. Security. Operations. Change board.
>
> When the record is ready, FireFly submits the deployment. Kaleido signs it. The platform syncs the receipt.
>
> Registration shows the same request with the address, transaction, block, and code hash. It answers: what exists? If the hashes match, the link is valid. If they do not match, the platform shows a mismatch.
>
> Council shows what each control role still does not accept. It shows the evidence gaps. It does not hide them.
>
> That is the platform. One record. One approval chain. One link to the chain.

---

## 9. Presentation checklist

Before the demo:

- [ ] Open `web/index.html` or serve the `web` directory.
- [ ] Open **Flow** and test **Play flow**.
- [ ] Clear the demo state if needed: run `localStorage.removeItem("onchain-registry-static-v1")` in the browser console.
- [ ] Set the browser to 1440 px width.
- [ ] Start at **Overview**.
- [ ] Use the **Platform tour** button.
- [ ] Have the **Registration** view ready for the link step.
- [ ] Have the **Council** view ready for the gap step.
- [ ] Do not use real bank data.
