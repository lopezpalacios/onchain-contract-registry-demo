/*
 * Static-only registry API.
 *
 * The browser is the whole runtime: HTML + CSS + JS. SQLite is a build-time
 * source used to generate data.js. Mutations (onboarding, approvals, mock sync)
 * are persisted in localStorage so the demo works from file:// or any static
 * host with no backend.
 */
(() => {
  "use strict";

  const STORAGE_KEY = "onchain-registry-static-v1";
  const seed = window.REGISTRY_DATA;
  if (!seed) {
    console.error("REGISTRY_DATA missing: load data.js before static-api.js");
    return;
  }

  const clone = (value) => JSON.parse(JSON.stringify(value));
  const now = () => new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const fail = (message, status = 400) => Promise.reject(Object.assign(new Error(message), { status }));
  const ok = (body) => Promise.resolve(clone(body));

  let db;
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    const parsed = saved ? JSON.parse(saved) : null;
    db = parsed && parsed.version === seed.version ? parsed : clone(seed);
  } catch {
    db = clone(seed);
  }

  function save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(db));
    } catch (error) {
      console.warn("Static demo state is in-memory only:", error);
    }
  }

  const riskRank = { low: 0, medium: 1, high: 2, critical: 3 };
  const purposeMeta = {
    tokenized_asset: ["token", "CMTAT", "Tokenized asset"],
    settlement: ["settlement", "DvP", "Settlement / value"],
    compliance: ["compliance", "RuleEngine", "Compliance / rule engine"],
    utility: ["utility", "Utility", "Utility / infrastructure"],
  };

  function recommendRisk(purpose, impact, environment) {
    if ((impact === "external" || impact === "both") && (purpose === "tokenized_asset" || purpose === "settlement")) return "critical";
    if (impact === "external" || purpose === "tokenized_asset" || purpose === "settlement" || purpose === "compliance") return "high";
    if (impact === "both") return "high";
    return environment === "PROD" ? "medium" : "low";
  }

  function staticHash(text) {
    let h1 = 0x811c9dc5;
    let h2 = 0x1000193;
    for (let i = 0; i < text.length; i += 1) {
      h1 ^= text.charCodeAt(i);
      h1 = Math.imul(h1, 0x01000193) >>> 0;
      h2 = Math.imul(h2 ^ text.charCodeAt(i), 0x85ebca6b) >>> 0;
    }
    return "0x" + [h1, h2, h1 ^ h2, (h1 + h2) >>> 0].map((n) => n.toString(16).padStart(16, "0")).join("");
  }

  function orgAncestors(orgUnitId) {
    const orgs = db.reference.org_units || [];
    const byId = new Map(orgs.map((o) => [o.id, o]));
    const result = new Set();
    let current = orgUnitId ? byId.get(orgUnitId) : null;
    while (current) {
      result.add(current.id);
      current = current.parent_id ? byId.get(current.parent_id) : null;
    }
    return result;
  }

  function actorHasRole(personId, roleCode, orgUnitId) {
    const today = new Date().toISOString().slice(0, 10);
    const allowed = orgUnitId ? orgAncestors(orgUnitId) : new Set();
    return (db.reference.role_assignments || []).some((ra) => {
      if (ra.person_id !== personId || ra.role_code !== roleCode || !ra.active) return false;
      if (ra.valid_from && ra.valid_from > today) return false;
      if (ra.valid_to && ra.valid_to < today) return false;
      return ra.scope_org_unit_id == null || !orgUnitId || allowed.has(ra.scope_org_unit_id);
    });
  }

  function eligibleActors(roleCode, orgUnitId) {
    const orgs = new Map((db.reference.org_units || []).map((o) => [o.id, o.name]));
    return (db.reference.people || [])
      .filter((p) => actorHasRole(p.id, roleCode, orgUnitId))
      .map((p) => {
        const assignment = (db.reference.role_assignments || []).find(
          (ra) => ra.person_id === p.id && ra.role_code === roleCode && ra.active
        );
        return {
          id: p.id,
          display_name: p.display_name,
          title: p.title,
          org_unit: assignment && assignment.scope_org_unit_id ? orgs.get(assignment.scope_org_unit_id) || "" : "",
        };
      });
  }

  function hydrateActors() {
    const groups = [db.approvals.deployments, db.approvals.templates, db.approvals.changes];
    for (const group of groups) {
      for (const request of group || []) {
        for (const gate of request.gates || []) {
          if (gate.decision !== "pending") {
            gate.eligible_actors = [];
            continue;
          }
          const actors = eligibleActors(gate.required_role, request.org_unit_id);
          gate.eligible_actors = actors;
          gate.eligible_actor_count = actors.length;
        }
      }
    }
  }

  function syncRegistration(req) {
    const reg = (db.registrations.items || []).find((item) => item.id === req.id);
    if (reg) {
      reg.gates = req.gates;
      reg.approved_gates = req.approved_gates;
      reg.pending_gates = req.pending_gates;
      reg.total_gates = req.total_gates;
      reg.status = req.status;
      reg.next_gate = req.next_gate;
      reg.readiness = req.readiness;
    }
    Object.values(db.contractDetails || {}).forEach((detail) => {
      if (detail.deployment_request_id === req.id) {
        detail.signoffs = req.gates;
        detail.deployment_status = req.status;
      }
    });
  }

  function recompute(request) {
    const gates = (request.gates || []).slice().sort((a, b) => Number(a.sequence) - Number(b.sequence));
    let nextFound = false;
    gates.forEach((gate) => {
      gate.is_next = gate.decision === "pending" && !nextFound ? 1 : 0;
      if (gate.is_next) nextFound = true;
    });
    request.gates = gates;
    request.total_gates = gates.length;
    request.approved_gates = gates.filter((g) => g.decision === "approved").length;
    request.pending_gates = gates.filter((g) => g.decision === "pending").length;
    request.next_gate = gates.find((g) => g.is_next) || null;
    if (request.next_gate) {
      request.next_gate.eligible_actors = eligibleActors(request.next_gate.required_role, request.org_unit_id);
      request.next_gate.eligible_actor_count = request.next_gate.eligible_actors.length;
    }
    if (request.pending_gates === 0 && request.status !== "deployed") request.status = "approved";
    else if (request.pending_gates > 0 && !["deployed", "rejected"].includes(request.status)) request.status = "in_review";
    if (request.template_status && request.template_status !== "approved") request.readiness = "Blocked: template not approved";
    else if (request.pending_gates > 0) request.readiness = "In review: approvals incomplete";
    else request.readiness = "Ready";
    return request;
  }

  function refreshSummary() {
    const requests = [
      ...(db.approvals.deployments || []),
      ...(db.approvals.templates || []),
      ...(db.approvals.changes || []),
    ];
    const gates = requests.flatMap((request) => request.gates || []);
    const unlinked = (db.discovery.queue || []).filter((item) => ["new", "triage", "quarantined"].includes(item.status)).length;
    const logical = db.summary.counts.logical_instances || 0;
    db.summary.counts.pending_gates = gates.filter((g) => g.decision === "pending").length;
    db.summary.counts.unlinked = unlinked;
    db.summary.counts.observed_contracts = logical + unlinked;
    db.summary.coverage = {
      registered: logical,
      observed: logical + unlinked,
      percent: logical + unlinked ? Math.round((logical / (logical + unlinked)) * 1000) / 10 : 0,
    };
    db.summary.approvals = (db.approvals.deployments || []).filter((r) => r.status === "in_review").slice(0, 5);
    db.discovery.counts = {
      new: (db.discovery.queue || []).filter((q) => q.status === "new").length,
      triage: (db.discovery.queue || []).filter((q) => q.status === "triage").length,
      quarantined: (db.discovery.queue || []).filter((q) => q.status === "quarantined").length,
      linked: (db.discovery.queue || []).filter((q) => q.status === "linked").length,
    };
    const items = db.registrations.items || [];
    db.registrations.summary = {
      total: items.length,
      pre_chain: items.filter((i) => i.link_state === "pre_chain").length,
      linked: items.filter((i) => (i.link_state || "").startsWith("linked")).length,
      hash_matches: items.filter((i) => i.link_state === "linked_match").length,
      hash_mismatches: items.filter((i) => i.link_state === "linked_mismatch").length,
      in_review: items.filter((i) => i.status === "in_review").length,
      blocked: items.filter((i) => (i.readiness || "").startsWith("Blocked")).length,
    };
    save();
  }

  function findGate(signoffId) {
    const groups = [
      { type: "deployment", list: db.approvals.deployments || [] },
      { type: "template", list: db.approvals.templates || [] },
      { type: "change", list: db.approvals.changes || [] },
    ];
    for (const group of groups) {
      for (const request of group.list) {
        const gate = (request.gates || []).find((g) => g.id === signoffId);
        if (gate) return { group, request, gate };
      }
    }
    return null;
  }

  function decideSignoff(signoffId, payload) {
    const found = findGate(signoffId);
    if (!found) return fail("signoff not found", 404);
    const { group, request, gate } = found;
    const decision = payload.decision;
    const actorId = payload.actor_id;
    if (!["approved", "rejected"].includes(decision)) return fail("decision must be approved or rejected");
    if (!actorId) return fail("actor_id is required");
    if (gate.decision !== "pending") return fail(`signoff is already ${gate.decision}`, 409);
    const actor = (db.reference.people || []).find((p) => p.id === actorId);
    if (!actor) return fail("actor not found", 403);
    const eligible = (gate.eligible_actors || []).map((a) => a.id);
    if (eligible.length && !eligible.includes(actorId)) return fail(`${actor.display_name} is not eligible for the ${gate.gate} gate`, 403);
    if (actor.display_name === request.requested_by_name) return fail("segregation of duties: the requester cannot approve this request", 409);
    if (decision === "approved") {
      const prior = (request.gates || []).filter((g) => Number(g.sequence) < Number(gate.sequence) && g.blocking && g.decision !== "approved");
      if (prior.length) return fail(`previous blocking gate(s) not approved: ${prior.map((g) => g.gate).join(", ")}`, 409);
      const already = (request.gates || []).find((g) => g.id !== gate.id && g.decision === "approved" && g.decided_by_name === actor.display_name);
      if (already) return fail(`four-eyes: ${actor.display_name} already approved the ${already.gate} gate on this object`, 409);
      if (group.type === "deployment") {
        const otherPending = (request.gates || []).filter((g) => g.id !== gate.id && g.decision === "pending").length;
        const today = new Date().toISOString().slice(0, 10);
        const auditOk = ["external", "internal"].includes(request.audit_status) && (!request.audit_valid_until || request.audit_valid_until >= today);
        if (otherPending === 0 && (request.template_status !== "approved" || !auditOk)) {
          return fail(`cannot complete approval: ${!auditOk ? "independent audit missing or expired" : "template not approved"}`, 409);
        }
      }
    }
    gate.decision = decision;
    gate.decided_by = actor.id;
    gate.decided_by_name = actor.display_name;
    gate.decided_at = now();
    gate.comments = payload.comments || "";
    gate.auth_method = "static-localStorage";
    recompute(request);
    if (decision === "rejected") request.status = "rejected";
    if (group.type === "deployment") syncRegistration(request);
    refreshSummary();
    return ok({
      ok: true,
      signoff_id: signoffId,
      decision,
      object_type: group.type,
      object_id: request.id,
      message: `${gate.gate} gate ${decision}`,
    });
  }

  function nextRequestId() {
    const year = new Date().getUTCFullYear();
    const prefix = `DR-${year}-`;
    const ids = (db.registrations.items || []).map((i) => i.id).filter((id) => id.startsWith(prefix));
    const max = ids.reduce((value, id) => Math.max(value, Number(id.split("-").pop()) || 0), 63);
    return `${prefix}${String(max + 1).padStart(4, "0")}`;
  }

  function createTemplate(payload, risk, templateId) {
    const [category, contractType, purposeLabel] = purposeMeta[payload.purpose];
    const audit = (payload.evidence || []).includes("audit");
    const created = now();
    const template = {
      id: templateId,
      template_key: "STATIC_" + templateId.slice(-8).toUpperCase(),
      name: payload.contract_name,
      version: "0.1.0",
      category,
      contract_type: contractType,
      description: payload.notes || `Static onboarding draft for ${payload.contract_name}`,
      status: "draft",
      source_repo: payload.source_repo || "pending",
      source_path: "pending",
      git_commit: "pending",
      compiler_version: "pending",
      evm_version: "pending",
      license: "TBD",
      initcode_hash: staticHash("draft-init:" + templateId),
      runtime_code_hash: staticHash("draft-runtime:" + templateId),
      abi_hash: null,
      audit_status: audit ? "external" : "none",
      audit_provider: audit ? "Requester-provided — unverified" : null,
      audit_valid_until: audit ? new Date(Date.now() + 31536000000).toISOString().slice(0, 10) : null,
      default_risk_tier: risk,
      owner_org_unit_id: payload.division_id,
      approved_at: null,
      retired_at: null,
      created_at: created,
      notes: "Created by the static onboarding wizard. Replace draft hashes with compiled artifacts.",
      deployments: 0,
      chains_used: 0,
      last_deployed_at: null,
      chain_names: null,
      live_instances: 0,
      audit_state: audit ? "expiring" : "none",
      audit_days_left: null,
      standards: [],
      instances: [],
    };
    db.templates.items.unshift(template);
    db.templateDetails[templateId] = {
      ...template,
      standards: [],
      parameters: [],
      instances: [],
      dependencies: [],
      documents: [],
      attestations: [],
      signoffs: [],
      used_by_ci: [],
      purpose_label: purposeLabel,
    };
    return template;
  }

  function onboarding(payload) {
    const name = (payload.contract_name || "").trim();
    if (!name) return fail("contract_name is required");
    if (!purposeMeta[payload.purpose]) return fail("purpose is invalid");
    if (!["new", "approved_params", "modified", "third_party"].includes(payload.code_source)) return fail("code_source is invalid");
    const chain = (db.reference.chains || []).find((c) => c.id === payload.chain_id);
    if (!chain) return fail("chain not found");
    if (chain.environment !== payload.environment) return fail(`chain is ${chain.environment}, request is ${payload.environment}`);
    const division = (db.reference.org_units || []).find((o) => o.id === payload.division_id);
    const owner = (db.reference.people || []).find((p) => p.id === payload.business_owner_id);
    if (!division) return fail("division not found");
    if (!owner) return fail("business owner not found");
    const minimum = recommendRisk(payload.purpose, payload.user_impact, payload.environment);
    const selected = payload.risk_tier === "auto" ? minimum : payload.risk_tier;
    if (riskRank[selected] < riskRank[minimum]) return fail(`risk tier ${selected} is below policy minimum ${minimum}; select ${minimum} or higher`);
    const evidence = (payload.evidence || []).filter((e) => e in db.reference.evidence_labels);
    let template;
    if (payload.code_source === "approved_params") {
      template = (db.templates.items || []).find((t) => t.id === payload.template_id);
      if (!template) return fail("template_id is required and must exist for approved-template reuse");
    } else {
      template = createTemplate(payload, selected, "tpl-static-" + Date.now().toString(36));
    }
    const requestId = nextRequestId();
    const created = now();
    const config = {
      contract_name: name,
      purpose: payload.purpose,
      code_source: payload.code_source,
      template_id: template.id,
      chain_id: payload.chain_id,
      environment: payload.environment,
      user_impact: payload.user_impact,
      risk_tier: selected,
      evidence: evidence.slice().sort(),
    };
    const configHash = staticHash(JSON.stringify(config));
    const manifestHash = staticHash(JSON.stringify({ config: configHash, template: template.id, evidence }));
    const platform = {
      firefly_kaleido: "Kaleido FireFly",
      safe_timelock: "Safe / Timelock",
      manual: "Manual developer wallet",
      factory: "Factory / CREATE2",
    }[payload.deployment_authority] || "Kaleido FireFly";
    const signingIdentity = payload.chain_id === "ch-besu-uat" ? "si-besu-uat-service" : payload.chain_id === "ch-besu-prod" ? "si-besu-service" : "si-eth-service";
    const policies = (db.reference.policies || []).filter((p) => p.object_type === "deployment" && p.risk_tier === selected).sort((a, b) => a.sequence - b.sequence);
    const gates = policies.map((p, index) => ({
      id: `so-${requestId.toLowerCase()}-${p.gate.toLowerCase().replaceAll(" ", "-")}`,
      object_type: "deployment",
      object_id: requestId,
      gate: p.gate,
      required_role: p.required_role,
      decision: "pending",
      decided_by: null,
      decided_by_name: null,
      decided_at: null,
      comments: null,
      evidence_uri: null,
      evidence_hash: null,
      document_id: null,
      auth_method: "seed",
      expires_at: null,
      created_at: created,
      sequence: p.sequence,
      blocking: p.blocking,
      risk_tier: selected,
      is_next: index === 0 ? 1 : 0,
      eligible_actor_count: eligibleActors(p.required_role, division.id).length,
      eligible_actors: index === 0 ? eligibleActors(p.required_role, division.id) : [],
    }));
    const jurisdiction = (division.legal_entity || "").includes("Luxembourg") || division.id.includes("lux") ? "LU" : "CH";
    const request = {
      id: requestId,
      template_id: template.id,
      template_name: template.name,
      template_version: template.version,
      template_status: template.status,
      template_runtime_hash: template.runtime_code_hash,
      chain_id: payload.chain_id,
      chain_name: chain.name,
      environment: payload.environment,
      chain_environment: chain.environment,
      product_name: name,
      legal_entity: division.legal_entity || "Financial Institution AG",
      jurisdiction,
      business_owner_name: owner.display_name,
      requested_by_name: "Priya Nair",
      org_unit: division.name,
      org_unit_id: division.id,
      risk_tier: selected,
      status: "in_review",
      readiness: template.status === "approved" ? "In review: approvals incomplete" : "Blocked: template not approved",
      config_hash: configHash,
      manifest_hash: manifestHash,
      salt: staticHash("salt:" + requestId),
      target_window: payload.target_window || "TBD — onboarding",
      change_ticket: "ONB-" + requestId.split("-").pop(),
      created_at: created,
      approved_at: null,
      deployment_platform: platform,
      signing_identity: signingIdentity,
      signing_identity_type: "service",
      audit_status: template.audit_status,
      audit_valid_until: template.audit_valid_until,
      evidence_json: JSON.stringify(evidence.slice().sort()),
      onboarding_source: payload.code_source,
      total_gates: gates.length,
      approved_gates: 0,
      pending_gates: gates.length,
      gates,
      next_gate: gates[0] || null,
      manifest_document: {},
      instance_id: null,
      address: null,
      address_eip55: null,
      deployment_tx: null,
      block_number: null,
      deployed_at: null,
      instance_runtime_hash: null,
      proxy_type: null,
      implementation_address: null,
      verification_status: null,
      verification_provider: null,
      instance_status: null,
      link_state: "pre_chain",
      linked_records: 0,
      implementation_count: 0,
      supporting_count: 0,
    };
    db.registrations.items.unshift(request);
    db.approvals.deployments.unshift(request);
    const required = new Set(["source_tests"]);
    if (payload.code_source !== "approved_params" || ["high", "critical"].includes(selected)) required.add("audit");
    if (["tokenized_asset", "settlement"].includes(payload.purpose) || ["external", "both"].includes(payload.user_impact)) { required.add("legal"); required.add("dpia"); }
    if (["high", "critical"].includes(selected)) required.add("dora");
    if (payload.purpose === "tokenized_asset") required.add("reserve");
    const missing = [...required].filter((e) => !evidence.includes(e));
    refreshSummary();
    return ok({
      ok: true,
      request_id: requestId,
      template_id: template.id,
      risk_tier: selected,
      status: "in_review",
      deployment_platform: platform,
      signing_identity: signingIdentity,
      gates: gates.map((g) => g.gate),
      provided_evidence: evidence,
      missing_evidence: missing,
      message: "Pre-chain registration created. No on-chain address exists until deployment.",
    });
  }

  function mockSync(payload) {
    const chainId = payload.chain_id || "ch-besu-prod";
    const chain = (db.reference.chains || []).find((c) => c.id === chainId) || { name: "Permissioned Ledger Production", environment: "PROD" };
    const stamp = Date.now().toString(36);
    const run = {
      id: "sr-static-" + stamp,
      chain_id: chainId,
      chain_name: chain.name,
      mode: "mock",
      from_block: 1844400,
      to_block: 1844401,
      blocks_scanned: 2,
      txs_scanned: 47,
      contracts_found: 1,
      contracts_matched: 0,
      unknown: 1,
      errors: 0,
      status: "success",
      started_at: now(),
      finished_at: now(),
      checkpoint_block: 1844401,
    };
    const address = "0x" + staticHash("static-sync:" + stamp).slice(2, 42);
    db.discovery.queue.unshift({
      id: "disc-static-" + stamp,
      chain_id: chainId,
      chain_name: chain.name,
      environment: chain.environment,
      address,
      runtime_code_hash: staticHash("static-runtime:" + stamp),
      tx_hash: staticHash("static-tx:" + stamp),
      deployer_address: "0x8e21784f4a55d8cf2c21db7511499874ea54905e",
      block_number: 1844401,
      first_seen_at: now(),
      status: "new",
      classification: "Static mock discovery: ERC-20-like selectors, no template match",
      risk_hint: "high",
      notes: "Generated by the static demo sync button. It remains unregistered to exercise the reconciliation queue.",
    });
    db.discovery.runs.unshift(run);
    refreshSummary();
    return ok({ ok: true, run_id: run.id, discovered: 1, matched: 0, unknown: 1, address });
  }

  async function api(path, options = {}) {
    const method = (options.method || "GET").toUpperCase();
    const pathname = path.split("?")[0];
    if (method === "GET") {
      if (pathname === "/api/summary") { refreshSummary(); return ok(db.summary); }
      if (pathname === "/api/contracts") return ok(db.contracts);
      if (pathname.startsWith("/api/contracts/")) {
        const id = decodeURIComponent(pathname.slice("/api/contracts/".length));
        return db.contractDetails[id] ? ok(db.contractDetails[id]) : fail("not found", 404);
      }
      if (pathname === "/api/templates") return ok(db.templates);
      if (pathname.startsWith("/api/templates/")) {
        const id = decodeURIComponent(pathname.slice("/api/templates/".length));
        return db.templateDetails[id] ? ok(db.templateDetails[id]) : fail("not found", 404);
      }
      if (pathname === "/api/approvals") { hydrateActors(); return ok(db.approvals); }
      if (pathname === "/api/registrations") { refreshSummary(); return ok(db.registrations); }
      if (pathname === "/api/reference") return ok(db.reference);
      if (pathname === "/api/discovery") return ok(db.discovery);
      if (pathname === "/api/controls") return ok(db.controls);
      if (pathname === "/api/council") return ok(db.council);
      return fail("unknown endpoint", 404);
    }
    if (method === "POST") {
      let payload = {};
      try { payload = options.body ? JSON.parse(options.body) : {}; } catch { return fail("invalid JSON"); }
      const match = pathname.match(/^\/api\/signoffs\/([^/]+)\/decision$/);
      if (match) return decideSignoff(decodeURIComponent(match[1]), payload);
      if (pathname === "/api/onboarding") return onboarding(payload);
      if (pathname === "/api/sync") return mockSync(payload);
      return fail("unknown endpoint", 404);
    }
    return fail("method not allowed", 405);
  }

  window.staticRegistryApi = api;
  window.staticRegistryReset = () => {
    db = clone(seed);
    save();
    window.location.reload();
  };
  refreshSummary();
})();
