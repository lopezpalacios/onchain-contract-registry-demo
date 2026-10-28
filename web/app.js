(() => {
  "use strict";

  const state = {
    summary: null,
    inventory: [],
    templates: [],
    templateMeta: { categories: [], risk: [] },
    approvals: { deployments: [], templates: [], changes: [] },
    discovery: { queue: [], runs: [], chains: [], counts: {} },
    controls: { coverage: [], exceptions: [], attestations: [], incidents: [], reserve: [], readiness: [], chains: [] },
    council: { personas: [], findings: [], compliance: [], ict: [], evidence_gaps: [], template_gaps: [], deployer_risk: [], reserve: [], summary: {} },
    registration: { items: [], summary: {} },
    reference: { chains: [], org_units: [], people: [], templates: [], policies: [], evidence_labels: {} },
    onboardingStep: 1,
    selectedRegistration: "DR-2026-0031",
    approvalIndex: {},
    view: "overview",
    loading: true,
  };

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[char]);

  const fmtNum = (value, digits = 0) => {
    if (value === null || value === undefined || Number.isNaN(Number(value))) return "—";
    return new Intl.NumberFormat("en-CH", { maximumFractionDigits: digits }).format(Number(value));
  };

  const fmtDate = (value) => {
    if (!value) return "—";
    const raw = String(value);
    const date = new Date(raw.includes("T") ? raw : `${raw}T00:00:00Z`);
    if (Number.isNaN(date.getTime())) return esc(raw);
    return new Intl.DateTimeFormat("en-GB", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" }).format(date);
  };

  const fmtDateTime = (value) => {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return esc(value);
    return new Intl.DateTimeFormat("en-GB", {
      day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "UTC",
    }).format(date) + " UTC";
  };

  const shortAddr = (address) => {
    if (!address) return "—";
    const value = String(address);
    return `${value.slice(0, 8)}…${value.slice(-6)}`;
  };

  const shortHash = (hash) => hash ? `${String(hash).slice(0, 10)}…${String(hash).slice(-6)}` : "—";

  const badge = (text, cls = "neutral") => `<span class="badge badge-${cls}">${esc(text)}</span>`;

  const riskBadge = (tier) => badge(tier || "unknown", tier === "critical" ? "critical" : tier === "high" ? "high" : tier === "medium" ? "medium" : "low");

  const statusBadge = (status) => {
    const map = {
      active: "low", deployed: "medium", approved: "low", draft: "neutral",
      in_review: "high", rejected: "critical", retired: "neutral", deprecated: "neutral",
      paused: "critical", quarantined: "critical", investigating: "high", contained: "medium",
      closed: "low", open: "critical", expired: "critical", valid: "low",
      new: "high", triage: "high", linked: "low", pending: "high",
      complete: "low", partial: "high", gap: "critical", remediated: "low",
      risk_accepted: "high", accepted: "medium",
    };
    return badge(status || "unknown", map[status] || "neutral");
  };

  const daysLeft = (value) => {
    if (!value) return null;
    const date = new Date(String(value).includes("T") ? value : `${value}T00:00:00Z`);
    if (Number.isNaN(date.getTime())) return null;
    return Math.ceil((date.getTime() - Date.now()) / 86400000);
  };

  const auditState = (status, validUntil) => {
    if (!status) return "unknown";
    if (status === "none") return "none";
    if (status === "self") return "self-assessed";
    const days = daysLeft(validUntil);
    if (days === null) return "unknown";
    if (days < 0) return "expired";
    if (days <= 60) return "expiring";
    return "valid";
  };

  const auditBadge = (state, days) => {
    if (!state) return badge("unknown", "neutral");
    const map = { valid: "low", expiring: "high", expired: "critical", none: "critical", "self-assessed": "high", unknown: "neutral" };
    const suffix = days !== null && days !== undefined && days >= 0 ? ` · ${days}d` : "";
    return badge(`${state}${suffix}`, map[state] || "neutral");
  };

  const chainClass = (name = "") => name.toLowerCase().includes("ethereum") ? "eth" : name.toLowerCase().includes("uat") ? "uat" : "besu";

  const chainPill = (name, environment = "") => {
    if (!name) return "—";
    return `<span class="chain-pill"><span class="chain-dot ${chainClass(name)}"></span>${esc(name)}${environment ? `<span class="muted tiny"> ${esc(environment)}</span>` : ""}</span>`;
  };

  const progress = (done, total) => {
    const pct = total ? Math.round((done / total) * 100) : 0;
    return `<div class="progress" aria-label="${done} of ${total} gates approved"><span style="width:${pct}%"></span></div>`;
  };

  function table(headers, rows, options = {}) {
    if (!rows.length) return `<div class="empty">${esc(options.empty || "No records.")}</div>`;
    return `<div class="table-wrap"><table><thead><tr>${headers.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.map((row) => `<tr class="${options.clickable ? "clickable" : ""}" ${options.clickable ? 'tabindex="0"' : ""} ${row.id ? `data-contract="${esc(row.id)}"` : row.registration ? `data-registration="${esc(row.registration)}"` : ""}>${row.cells.map((cell) => `<td>${cell}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  }

  function detailGrid(items, extraClass = "") {
    return `<div class="detail-grid ${extraClass}">${items.map(([label, value]) => `<div class="detail-cell"><span>${esc(label)}</span><strong>${value ?? "—"}</strong></div>`).join("")}</div>`;
  }

  function sectionTitle(text) {
    return `<div class="detail-section"><h4>${esc(text)}</h4>`;
  }

  let modalLastFocus = null;

  function openModal(html) {
    modalLastFocus = document.activeElement;
    $("#modal-content").innerHTML = html;
    $("#modal-backdrop").classList.add("open");
    document.body.style.overflow = "hidden";
    $(".topbar")?.setAttribute("inert", "");
    $(".shell")?.setAttribute("inert", "");
    const close = $(".modal-close");
    if (close) close.focus();
  }

  function closeModal() {
    $("#modal-backdrop").classList.remove("open");
    document.body.style.overflow = "";
    $(".topbar")?.removeAttribute("inert");
    $(".shell")?.removeAttribute("inert");
    if (modalLastFocus && modalLastFocus.isConnected) modalLastFocus.focus();
  }

  function wireModal() {
    $$(".modal-close, [data-close]").forEach((el) => el.addEventListener("click", closeModal));
    $$(".modal-tab").forEach((tab) => tab.addEventListener("click", () => {
      $$(".modal-tab").forEach((t) => t.classList.toggle("active", t === tab));
      $$(".modal-panel").forEach((panel) => panel.classList.toggle("active", panel.id === tab.dataset.panel));
    }));
    $$("[data-copy]").forEach((button) => button.addEventListener("click", async () => {
      const value = button.dataset.copy;
      try {
        await navigator.clipboard.writeText(value);
        toast("Address copied to clipboard.", "success");
      } catch {
        toast(value, "info");
      }
    }));
  }

  function toast(message, type = "info", timeout = 4200) {
    const el = document.createElement("div");
    el.className = `toast ${type}`;
    el.textContent = message;
    $("#toast-wrap").appendChild(el);
    window.setTimeout(() => el.remove(), timeout);
  }

  async function api(path, options = {}) {
    if (window.staticRegistryApi) return window.staticRegistryApi(path, options);
    const response = await fetch(path, {
      headers: { "Content-Type": "application/json" },
      ...options,
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(body.error || `Request failed (${response.status})`);
      error.status = response.status;
      throw error;
    }
    return body;
  }

  // -----------------------------------------------------------------------
  // Navigation
  // -----------------------------------------------------------------------

  function switchView(view, updateHash = true) {
    if (!document.getElementById(`view-${view}`)) return;
    state.view = view;
    $$(".view").forEach((section) => section.classList.toggle("active", section.id === `view-${view}`));
    $$(".nav-link").forEach((link) => {
      const active = link.dataset.view === view;
      link.classList.toggle("active", active);
      link.setAttribute("aria-selected", String(active));
    });
    if (updateHash) history.replaceState(null, "", `#${view}`);
    const activeLink = $(".nav-link.active");
    if (activeLink) activeLink.scrollIntoView({ inline: "center", block: "nearest", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    window.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  }

  // -----------------------------------------------------------------------
  // Overview
  // -----------------------------------------------------------------------

  function renderKpis() {
    const c = state.summary.counts;
    const items = [
      ["Registered contracts", fmtNum(c.logical_instances), `${c.critical_high} high or critical`],
      ["Approved templates", fmtNum(c.templates_approved), `${c.templates} in catalogue`],
      ["Pending gates", fmtNum(c.pending_gates), `${state.summary.approvals.length} requests in review`, "alert"],
      ["Registry coverage", `${state.summary.coverage.percent.toFixed(1)}<small>%</small>`, `${c.observed_contracts} observed on-chain`],
      ["Reserve coverage", `${state.summary.reserve.coverage_percent.toFixed(1)}<small>%</small>`, `${fmtNum(state.summary.reserve.gold_grams)} g vs ${fmtNum(state.summary.reserve.supply_grams)} g supply`],
      ["Control pass rate", `${state.summary.control_pass_percent}<small>%</small>`, `${c.control_exceptions} exceptions`],
    ];
    $("#kpi-grid").innerHTML = items.map(([label, value, sub, cls]) => `
      <div class="kpi ${cls || ""}">
        <div class="kpi-label">${esc(label)}</div>
        <div class="kpi-value">${value}</div>
        <div class="kpi-sub">${sub}</div>
      </div>`).join("");
  }

  function renderRisk() {
    const risk = state.summary.risk || [];
    const colors = { critical: "#e60000", high: "#b86e00", medium: "#0f5e8c", low: "#1a7a4a" };
    const total = risk.reduce((sum, item) => sum + item.count, 0);
    let cursor = 0;
    const stops = [];
    risk.forEach((item) => {
      const start = cursor;
      cursor += total ? (item.count / total) * 100 : 0;
      stops.push(`${colors[item.risk_tier] || "#999"} ${start}% ${cursor}%`);
    });
    $("#risk-donut").style.background = `conic-gradient(${stops.join(", ") || "#eee 0 100%"})`;
    $("#risk-total").textContent = fmtNum(total);
    $("#risk-legend").innerHTML = risk.map((item) => `
      <div class="legend-row">
        <span class="legend-dot" style="background:${colors[item.risk_tier] || "#999"}"></span>
        <span>${esc(item.risk_tier)}</span>
        <span class="count">${item.count}</span>
      </div>`).join("");

    const groups = {};
    state.templates.forEach((template) => {
      groups[template.category] = (groups[template.category] || 0) + 1;
    });
    const max = Math.max(...Object.values(groups), 1);
    $("#category-bars").innerHTML = Object.entries(groups)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([name, count]) => `
        <div class="bar-row">
          <div class="bar-label">${esc(name)}</div>
          <div class="bar-track"><div class="bar-fill" style="width:${(count / max) * 100}%"></div></div>
          <div class="bar-value">${count}</div>
        </div>`).join("");
  }

  function renderReserve() {
    const reserve = state.summary.reserve;
    const tokens = (state.controls.reserve || []).filter((row) => row.counts_toward_reserve === 1 && row.reserve_state === "current");
    const bars = tokens.reduce((sum, row) => sum + (row.bars_count || 0), 0);
    const low = reserve.coverage_percent < 100;
    $("#reserve-card").innerHTML = `
      <div class="reserve-hero">
        <div class="reserve-pct">${reserve.coverage_percent.toFixed(1)}</div>
        <div class="reserve-unit">% covered</div>
      </div>
      <div class="small muted">Attested gold vs outstanding token supply, excluding test and retired pools.</div>
      <div class="reserve-meta">
        <div><span>Token supply</span><strong>${fmtNum(reserve.supply_grams)} g</strong></div>
        <div><span>Attested gold</span><strong>${fmtNum(reserve.gold_grams)} g</strong></div>
        <div><span>Bars in attestation</span><strong>${fmtNum(bars)}</strong></div>
        <div><span>Next attestation</span><strong>15 Nov 2026</strong></div>
      </div>
      <div class="alert-list mt-16">
        ${tokens.map((token) => `
          <div class="alert-item">
            <span class="alert-mark ${low ? "" : "green"}"></span>
            <div class="alert-main">
              <div class="alert-title">${esc(token.product_name)}</div>
              <div class="alert-sub">${esc(token.symbol)} · ${fmtNum(token.total_supply)} supply · ${fmtNum(token.gold_grams)} g gold</div>
            </div>
            <span class="badge ${low ? "badge-critical" : "badge-low"}">${(token.coverage_ratio * 100).toFixed(1)}%</span>
          </div>`).join("") || `<div class="empty">No reserve snapshot.</div>`}
      </div>
      <div class="form-note">Public and ledger tokens use separate reserve pools. UAT and retired supply are excluded.</div>`;
  }

  function approvalRow(request) {
    const total = request.total_gates || 0;
    const done = request.approved_gates || 0;
    return `
      <div class="alert-item" style="cursor:pointer" data-approval-request="${esc(request.id)}">
        <span class="alert-mark ${request.readiness?.startsWith("Blocked") ? "" : request.readiness?.startsWith("In review") ? "amber" : "green"}"></span>
        <div class="alert-main">
          <div class="alert-title">${esc(request.product_name)}</div>
          <div class="alert-sub">${esc(request.id)} · ${esc(request.chain_name)} · ${esc(request.next_gate || "complete")}</div>
        </div>
        <div class="right">
          ${statusBadge(request.status)}
          <div class="tiny muted mt-8">${done}/${total} gates</div>
        </div>
      </div>`;
  }

  function renderApprovalPreview() {
    const requests = state.summary.approvals || [];
    $("#approval-preview").innerHTML = requests.length
      ? requests.map(approvalRow).join("")
      : `<div class="empty">No deployment requests in review.</div>`;
  }

  function renderAlerts() {
    const alerts = [];
    (state.summary.alerts || []).forEach((alert) => {
      alerts.push({
        cls: alert.alert_level === "expired" ? "" : alert.alert_level === "critical" ? "" : "amber",
        severity: alert.alert_level === "expired" || alert.alert_level === "critical" ? 0 : 3,
        title: `${alert.attestation_type.replaceAll("_", " ")} · ${alert.subject}`,
        sub: `Expires ${fmtDate(alert.expires_at)} · ${alert.days_left} days`,
        badge: badge(alert.alert_level === "expired" ? "expired" : "expiring", alert.alert_level === "expired" ? "critical" : "high"),
        view: "controls",
      });
    });
    (state.discovery.queue || []).filter((item) => ["new", "triage", "quarantined"].includes(item.status)).forEach((item) => {
      alerts.push({
        cls: item.status === "quarantined" ? "" : "amber",
        severity: item.status === "quarantined" ? 0 : item.status === "triage" ? 1 : 2,
        title: `Unregistered contract · ${shortAddr(item.address)}`,
        sub: `${item.chain_name} · ${item.classification || item.status}`,
        badge: statusBadge(item.status),
        view: "reconciliation",
      });
    });
    (state.controls.exceptions || []).forEach((item) => {
      alerts.push({
        cls: "amber",
        severity: 1,
        title: `${item.control_code} · ${item.product_name}`,
        sub: `${item.control_name} · ${item.status}`,
        badge: badge(item.status, "high"),
        view: "controls",
      });
    });
    (state.council.findings || []).filter((f) => f.status === "open" && ["critical", "high"].includes(f.severity)).forEach((f) => {
      alerts.push({
        cls: f.severity === "critical" ? "" : "amber",
        severity: f.severity === "critical" ? 0 : 1,
        title: `${f.persona_name} · ${f.title}`,
        sub: `${f.owner_name || "unassigned"} · due ${fmtDate(f.due_date)}`,
        badge: riskBadge(f.severity),
        view: "council",
      });
    });
    alerts.sort((a, b) => a.severity - b.severity || a.title.localeCompare(b.title));
    $("#alert-count").textContent = `${alerts.length} signals`;
    const visible = alerts.slice(0, 6);
    $("#alert-preview").innerHTML = visible.length
      ? visible.map((item) => `
        <div class="alert-item" style="cursor:pointer" data-nav="${esc(item.view)}">
          <span class="alert-mark ${item.cls}"></span>
          <div class="alert-main">
            <div class="alert-title">${esc(item.title)}</div>
            <div class="alert-sub">${esc(item.sub)}</div>
          </div>
          ${item.badge}
        </div>`).join("") + (alerts.length > 6 ? `<div class="alert-item" style="cursor:pointer" data-nav="council"><span class="alert-mark amber"></span><div class="alert-main"><div class="alert-title">+${alerts.length - 6} more signals</div><div class="alert-sub">Open Council for findings or Reconciliation for unknown contracts.</div></div><span class="badge badge-neutral">view</span></div>` : "")
      : `<div class="empty">Nothing needs attention.</div>`;
  }

  function renderRecent() {
    const rows = (state.summary.recent_deployments || []).map((item) => ({
      id: item.id,
      cells: [
        `<div class="row-title">${esc(item.product_name)}</div><div class="row-sub">${esc(item.template_name)} ${esc(item.template_version)}</div>`,
        chainPill(item.chain_name, item.environment),
        `<div class="small">${esc(item.business_owner || "—")}</div><div class="row-sub">${esc(item.org_unit || "")}</div>`,
        riskBadge(item.risk_tier),
        statusBadge(item.status),
        `<span class="small nowrap">${fmtDate(item.deployed_at)}</span>`,
      ],
    }));
    $("#recent-table").innerHTML = table(["Contract", "Chain", "Owner", "Risk", "Status", "Deployed"], rows, { clickable: true, empty: "No deployments." });
    const latest = (state.discovery.runs || [])[0];
    $("#last-sync").textContent = latest ? fmtDateTime(latest.finished_at || latest.started_at) : "—";
    $("#generated-at").textContent = fmtDateTime(state.summary.generated_at);
  }

  function renderOverview() {
    renderKpis();
    renderRisk();
    renderReserve();
    renderApprovalPreview();
    renderAlerts();
    renderRecent();
  }

  // -----------------------------------------------------------------------
  // Registration: pre-chain record -> on-chain instance
  // -----------------------------------------------------------------------

  function linkBadge(state) {
    if (state === "linked_match") return badge("hash match", "low");
    if (state === "linked_mismatch") return badge("hash mismatch", "critical");
    return badge("pre-chain", "neutral");
  }

  function renderRegistration() {
    const data = state.registration || { items: [], summary: {} };
    const items = data.items || [];
    if (!items.length) {
      $("#registration-count").textContent = "No registrations";
      $("#registration-kpis").innerHTML = "";
      $("#registration-receipt").innerHTML = `<div class="empty">No deployment requests.</div>`;
      $("#registration-lifecycle").innerHTML = `<div class="empty">No lifecycle.</div>`;
      $("#registration-table").innerHTML = `<div class="empty">No records.</div>`;
      return;
    }
    if (!items.some((i) => i.id === state.selectedRegistration)) {
      state.selectedRegistration = (items.find((i) => i.id === "DR-2026-0031") || items[0]).id;
    }
    const selected = items.find((i) => i.id === state.selectedRegistration) || items[0];
    const s = data.summary || {};
    $("#registration-count").textContent = `${s.total || items.length} registrations · ${s.pre_chain || 0} pre-chain · ${s.linked || 0} linked`;
    $("#registration-selected-id").textContent = selected.id;

    $("#registration-kpis").innerHTML = [
      ["Registration records", s.total || items.length, "Pre-chain + deployed"],
      ["Pre-chain only", s.pre_chain || 0, "No on-chain address yet"],
      ["Linked to chain", s.linked || 0, "Address + tx + block"],
      ["Hash matches", s.hash_matches || 0, "Template = runtime code", "low"],
      ["Hash mismatches", s.hash_mismatches || 0, "Investigate immediately", s.hash_mismatches ? "alert" : ""],
      ["In review / blocked", `${s.in_review || 0} / ${s.blocked || 0}`, "Approvals / readiness"],
    ].map(([label, value, sub, cls]) => `<div class="kpi ${cls || ""}"><div class="kpi-label">${esc(label)}</div><div class="kpi-value">${value}</div><div class="kpi-sub">${esc(sub)}</div></div>`).join("");

    const manifest = selected.manifest_document || {};
    const linked = Boolean(selected.instance_id);
    const hashMatch = selected.link_state === "linked_match";
    $("#registration-receipt").innerHTML = `
      <div class="flex gap-8 center" style="flex-wrap:wrap;margin-bottom:14px">
        ${statusBadge(selected.status)}
        ${linkBadge(selected.link_state)}
        ${riskBadge(selected.risk_tier)}
        ${selected.readiness ? `<span class="badge ${selected.readiness.startsWith("Blocked") ? "badge-critical" : "badge-neutral"}">${esc(selected.readiness)}</span>` : ""}
      </div>
      ${detailGrid([
        ["Product", esc(selected.product_name)],
        ["Template", `${esc(selected.template_name)} <span class="mono">v${esc(selected.template_version)}</span>`],
        ["Chain / environment", `${esc(selected.chain_name)} · ${esc(selected.environment)}`],
        ["Legal entity", esc(selected.legal_entity)],
        ["Jurisdiction", esc(selected.jurisdiction)],
        ["Business owner", esc(selected.business_owner_name)],
        ["Requested by", esc(selected.requested_by_name)],
        ["Org unit", esc(selected.org_unit)],
        ["Created", fmtDateTime(selected.created_at)],
        ["Target window", esc(selected.target_window || "—")],
        ["Change ticket", esc(selected.change_ticket || "—")],
        ["Deployment platform", esc(selected.deployment_platform || "—")],
        ["Signing identity", `${esc(selected.signing_identity || "—")} ${badge(selected.signing_identity_type || "key", "neutral")}`],
        ["Config hash", `<span class="mono">${esc(shortHash(selected.config_hash))}</span>`],
        ["Manifest hash", `<span class="mono">${esc(shortHash(selected.manifest_hash))}</span>`],
        ["Salt", `<span class="mono">${esc(shortHash(selected.salt))}</span>`],
        ["Template runtime hash", `<span class="mono">${esc(shortHash(selected.template_runtime_hash))}</span>`],
        ["On-chain runtime hash", selected.instance_runtime_hash ? `<span class="mono">${esc(shortHash(selected.instance_runtime_hash))}</span>` : "—"],
        ["Template status", statusBadge(selected.template_status)],
        ["Audit valid until", fmtDate(selected.audit_valid_until)],
      ])}
      <div class="detail-section">
        <h4>Approval progress</h4>
        <div class="flex between center gap-12"><span class="small">${selected.approved_gates || 0} of ${selected.total_gates || 0} gates approved</span>${selected.pending_gates ? badge(`${selected.pending_gates} pending`, "high") : badge("complete", "low")}</div>
        ${progress(selected.approved_gates || 0, selected.total_gates || 0)}
        ${selected.next_gate ? `<div class="flex between center gap-12" style="margin-top:10px"><span class="tiny muted">Next: ${esc(selected.next_gate.required_role)}</span><button class="btn btn-primary btn-sm" data-gate="${esc(selected.next_gate.id)}">Review ${esc(selected.next_gate.gate)}</button></div>` : ""}
      </div>
      ${linked ? `
        <div class="detail-section"><h4>On-chain link</h4>
          <div class="address-box">${esc(selected.address_eip55 || selected.address)}<button class="copy-btn" data-copy="${esc(selected.address)}">Copy</button></div>
          ${detailGrid([
            ["Instance", `<button class="card-link" data-contract="${esc(selected.instance_id)}">${esc(selected.instance_id)} →</button>`],
            ["Status", statusBadge(selected.instance_status)],
            ["Deployment tx", `<span class="mono">${esc(shortHash(selected.deployment_tx))}</span>`],
            ["Block", fmtNum(selected.block_number)],
            ["Deployed", fmtDateTime(selected.deployed_at)],
            ["Proxy", esc(selected.proxy_type || "none")],
            ["Verification", `${esc(selected.verification_provider || "—")} ${badge(selected.verification_status, selected.verification_status === "exact" ? "low" : "high")}`],
            ["Linked records", `${selected.linked_records || 1} total · ${selected.implementation_count || 0} impl · ${selected.supporting_count || 0} supporting`],
          ])}
          <div class="form-note">Same <strong>${esc(selected.id)}</strong> record now resolves to <span class="mono">${esc(shortAddr(selected.address))}</span>. The template and runtime hashes are ${hashMatch ? "identical" : "different — investigate"}.</div>
        </div>` : `
        <div class="alert-item" style="margin-top:16px">
          <span class="alert-mark amber"></span>
          <div class="alert-main"><div class="alert-title">Pre-chain registration — no on-chain address yet</div><div class="alert-sub">The record exists as a deployment request. After the deployment transaction is signed and mined, the worker links the address, transaction, block and runtime code hash back to this same request ID.</div></div>
        </div>
        <div class="detail-section"><h4>Manifest</h4>
          ${manifest.title ? `<div class="link-item"><span class="link-relation">manifest</span><span>${esc(manifest.title)}</span><span class="mono tiny">${esc(shortHash(manifest.sha256))}</span></div>` : `<div class="empty">No manifest document attached yet.</div>`}
        </div>`}
    `;

    const step = (num, label, done, title, sub) => `<div class="timeline-item ${done ? "done" : "pending"}"><div class="timeline-date">${num} · ${esc(label)}</div><div class="timeline-title">${esc(title)}</div><div class="timeline-sub">${esc(sub)}</div></div>`;
    $("#registration-lifecycle").innerHTML = `<div class="timeline">
      ${step("01", "TEMPLATE", selected.template_status === "approved", `${selected.template_name} v${selected.template_version}`, `${selected.template_status} · audit ${selected.audit_status || "—"}`)}
      ${step("02", "PRE-CHAIN", true, "Deployment request registered", `${fmtDate(selected.created_at)} · ${selected.id}`)}
      ${step("03", "SIGN-OFFS", (selected.pending_gates || 0) === 0 && (selected.total_gates || 0) > 0, "Business and control gates", `${selected.approved_gates || 0}/${selected.total_gates || 0} approved`)}
      ${step("04", "MANIFEST", Boolean(selected.manifest_hash), "Deployment manifest hash", selected.manifest_hash ? `${shortHash(selected.manifest_hash)} · ${manifest.title ? "document attached" : "document not attached"}` : "not attached")}
      ${step("05", "DEPLOYMENT", Boolean(selected.deployment_tx), "Transaction signed and mined", selected.deployment_tx ? shortHash(selected.deployment_tx) : "waiting for deployment")}
      ${step("06", "ON-CHAIN", Boolean(selected.instance_id), "Contract instance registered", selected.instance_id ? `${shortAddr(selected.address)} · block ${fmtNum(selected.block_number)}` : "no address yet")}
    </div>`;

    const rows = items.map((item) => ({
      registration: item.id,
      cells: [
        `<div class="row-title">${esc(item.id)}</div><div class="row-sub">${esc(item.product_name)}</div>`,
        `<div class="small">${esc(item.template_name)}</div><div class="row-sub">v${esc(item.template_version)}</div>`,
        chainPill(item.chain_name, item.environment),
        statusBadge(item.status),
        `<span class="small">${item.approved_gates || 0}/${item.total_gates || 0}</span>`,
        item.instance_id ? `<span class="mono">${esc(shortAddr(item.address_eip55 || item.address))}</span><div class="row-sub">block ${fmtNum(item.block_number)}</div>` : `<span class="badge badge-neutral">no address yet</span>`,
        linkBadge(item.link_state),
      ],
    }));
    $("#registration-table").innerHTML = table(["Registration", "Template", "Chain", "Status", "Gates", "On-chain contract", "Link"], rows, { clickable: true, empty: "No registrations." });
  }

  // -----------------------------------------------------------------------
  // Onboarding wizard
  // -----------------------------------------------------------------------

  const PURPOSE_LABELS = {
    tokenized_asset: "Tokenized asset",
    settlement: "Settlement / value",
    compliance: "Compliance / rule engine",
    utility: "Utility / infrastructure",
  };

  const SOURCE_LABELS = {
    new: "New template from scratch",
    approved_params: "Approved template, new parameters",
    modified: "Approved template, modified code",
    third_party: "Third-party / OSS template",
  };

  const RISK_RANK = { low: 0, medium: 1, high: 2, critical: 3 };

  const AUTHORITY_LABELS = {
    firefly_kaleido: "FireFly under Kaleido",
    safe_timelock: "Safe / Timelock",
    factory: "Factory / CREATE2",
    manual: "Manual developer wallet",
  };

  function recommendedRisk(purpose, impact, environment) {
    if ((impact === "external" || impact === "both") && (purpose === "tokenized_asset" || purpose === "settlement")) return "critical";
    if (impact === "external" || purpose === "tokenized_asset" || purpose === "settlement" || purpose === "compliance") return "high";
    if (impact === "both") return "high";
    return environment === "PROD" ? "medium" : "low";
  }

  function requiredEvidence(purpose, source, impact, risk) {
    const required = new Set(["source_tests"]);
    if (source !== "approved_params" || risk === "high" || risk === "critical") required.add("audit");
    if (purpose === "tokenized_asset" || purpose === "settlement" || impact === "external" || impact === "both") {
      required.add("legal");
      required.add("dpia");
    }
    if (risk === "high" || risk === "critical") required.add("dora");
    if (purpose === "tokenized_asset") required.add("reserve");
    return required;
  }

  function onboardingValues() {
    const chainId = $("#ob-chain").value;
    const chain = (state.reference.chains || []).find((c) => c.id === chainId) || {};
    const source = $("#ob-source").value;
    const purpose = $("#ob-purpose").value;
    const impact = $("#ob-impact").value;
    const environment = chain.environment || "UAT";
    const selectedRisk = $("#ob-risk").value;
    const policyRisk = recommendedRisk(purpose, impact, environment);
    const risk = selectedRisk === "auto" ? policyRisk : selectedRisk;
    const evidence = $$(".ob-evidence:checked").map((el) => el.value);
    return {
      contract_name: ($("#ob-name").value || "").trim(),
      purpose,
      code_source: source,
      template_id: source === "approved_params" ? $("#ob-template").value : null,
      division_id: $("#ob-division").value,
      business_owner_id: $("#ob-owner").value,
      requested_by: "p-priya",
      chain_id: chainId,
      environment,
      user_impact: impact,
      risk_tier: selectedRisk,
      deployment_authority: $("#ob-authority").value,
      evidence,
      source_repo: ($("#ob-source-ref").value || "").trim(),
      target_window: ($("#ob-window").value || "").trim(),
      notes: ($("#ob-notes").value || "").trim(),
      computed_risk: risk,
      policy_risk: policyRisk,
      risk_below_floor: RISK_RANK[risk] < RISK_RANK[policyRisk],
    };
  }

  function populateOnboarding() {
    const ref = state.reference || {};
    if (!ref.chains || !ref.chains.length) return;
    const chainSelect = $("#ob-chain");
    if (!chainSelect.options.length) {
      chainSelect.innerHTML = ref.chains.map((c) => `<option value="${esc(c.id)}">${esc(c.name)} · ${esc(c.environment)}</option>`).join("");
      const preferred = ref.chains.find((c) => c.id === "ch-besu-uat") || ref.chains[0];
      chainSelect.value = preferred.id;
    }
    const division = $("#ob-division");
    if (!division.options.length) {
      division.innerHTML = ref.org_units.map((o) => `<option value="${esc(o.id)}">${esc(o.name)} — ${esc(o.division)}</option>`).join("");
      division.value = "org-gwm-da";
    }
    const owner = $("#ob-owner");
    if (!owner.options.length) {
      owner.innerHTML = ref.people.map((p) => `<option value="${esc(p.id)}">${esc(p.display_name)} — ${esc(p.title || "")}</option>`).join("");
      owner.value = "p-elena";
    }
    const template = $("#ob-template");
    if (!template.options.length) {
      template.innerHTML = ref.templates.map((t) => `<option value="${esc(t.id)}">${esc(t.name)} v${esc(t.version)}</option>`).join("");
      template.value = ref.templates.find((t) => t.id === "tpl-cmtat-300")?.id || ref.templates[0]?.id || "";
    }
    const source = $("#ob-source");
    $("#ob-template-row").style.display = source.value === "approved_params" ? "" : "none";
  }

  function onboardingReviewHtml(values) {
    const risk = values.computed_risk;
    const gates = (state.reference.policies || []).filter((p) => p.object_type === "deployment" && p.risk_tier === risk).sort((a, b) => a.sequence - b.sequence);
    const required = requiredEvidence(values.purpose, values.code_source, values.user_impact, risk);
    const missing = [...required].filter((e) => !values.evidence.includes(e));
    return `
      ${values.risk_below_floor ? `<div class="alert-item" style="margin-bottom:12px"><span class="alert-mark"></span><div class="alert-main"><div class="alert-title">Risk below policy minimum</div><div class="alert-sub">Selected ${esc(values.computed_risk)}, policy minimum ${esc(values.policy_risk)}. This request cannot be created without a documented risk acceptance.</div></div></div>` : ""}
      <div class="review-grid">
        <div><span>Contract</span><strong>${esc(values.contract_name || "—")}</strong></div>
        <div><span>Purpose</span><strong>${esc(PURPOSE_LABELS[values.purpose] || values.purpose)}</strong></div>
        <div><span>Path</span><strong>${esc(SOURCE_LABELS[values.code_source] || values.code_source)}</strong></div>
        <div><span>Risk</span><strong>${riskBadge(risk)}</strong></div>
        <div><span>Chain</span><strong>${esc((state.reference.chains.find((c) => c.id === values.chain_id) || {}).name || values.chain_id)} · ${esc(values.environment)}</strong></div>
        <div><span>Users</span><strong>${esc(values.user_impact)}</strong></div>
        <div><span>Deployment</span><strong>${esc(AUTHORITY_LABELS[values.deployment_authority] || values.deployment_authority)}</strong></div>
        <div><span>Gates</span><strong>${gates.length} pending gates</strong></div>
      </div>
      <div class="detail-section"><h4>Required gates</h4><div>${gates.map((g) => `<span class="chip">${esc(g.gate)}</span>`).join("") || `<span class="muted small">No deployment gate policy for this tier.</span>`}</div></div>
      <div class="detail-section"><h4>Evidence gaps</h4><div>${missing.length ? missing.map((e) => `<span class="chip red">${esc(state.reference.evidence_labels[e] || e)}</span>`).join("") : `<span class="chip green">All required evidence declared</span>`}</div><div class="form-note">Evidence is <strong>declared</strong>, not verified. Documents and hashes must be linked before approval.</div></div>
      <div class="form-note">This creates a <strong>pre-chain</strong> deployment request. FireFly/Kaleido will submit the signed deployment later. No on-chain address is created by this step.</div>`;
  }

  function updateOnboardingPreview() {
    if (!state.reference.chains || !state.reference.chains.length) return;
    const v = onboardingValues();
    const risk = v.computed_risk;
    const gates = (state.reference.policies || []).filter((p) => p.object_type === "deployment" && p.risk_tier === risk).sort((a, b) => a.sequence - b.sequence);
    const required = requiredEvidence(v.purpose, v.code_source, v.user_impact, risk);
    const missing = [...required].filter((e) => !v.evidence.includes(e));
    const path = v.code_source === "approved_params" ? "Reuse approved template → deployment request" : "Draft template → template assurance → deployment request";
    $("#onboarding-preview").innerHTML = `
      <div class="preview-block"><div class="preview-label">Registration path</div><div class="preview-value">${esc(path)}</div></div>
      <div class="preview-block"><div class="preview-label">Risk tier</div><div class="preview-value">${riskBadge(risk)} ${v.risk_tier === "auto" ? `<span class="tiny muted">auto from purpose, users and environment</span>` : ""}</div>${v.risk_below_floor ? `<div class="field-error" style="display:block;margin-top:6px">Policy minimum is ${esc(v.policy_risk)}. Select ${esc(v.policy_risk)} or higher, or attach a documented risk acceptance.</div>` : `<div class="tiny muted" style="margin-top:4px">Policy minimum: ${esc(v.policy_risk)}</div>`}</div>
      <div class="preview-block"><div class="preview-label">Deployment authority</div><div class="preview-value">${esc(AUTHORITY_LABELS[v.deployment_authority] || v.deployment_authority)}</div><div class="tiny muted">Signing identity: ${v.chain_id === "ch-besu-uat" ? "si-besu-uat-service" : v.chain_id === "ch-besu-prod" ? "si-besu-service" : "si-eth-service"}</div></div>
      <div class="preview-block"><div class="preview-label">Required gates (${gates.length})</div><div>${gates.map((g) => `<span class="chip">${esc(g.gate)}</span>`).join("") || `<span class="muted small">No policy rows.</span>`}</div></div>
      <div class="preview-block"><div class="preview-label">Evidence check</div><div class="preview-list"><div><span>Declared</span><span>${v.evidence.length}</span></div><div><span>Required</span><span>${required.size}</span></div></div><div class="mt-8">${missing.length ? missing.map((e) => `<span class="chip red">${esc(state.reference.evidence_labels[e] || e)}</span>`).join("") : `<span class="chip green">complete</span>`}</div></div>
      <div class="form-note">Pre-chain only: no address, transaction or runtime hash exists until deployment. The same request ID will link to the FireFly/Kaleido deployment receipt.</div>`;
    $("#onboarding-review").innerHTML = onboardingReviewHtml(v);
  }

  function setNameError(message) {
    const input = $("#ob-name");
    const error = $("#ob-name-error");
    input.setAttribute("aria-invalid", message ? "true" : "false");
    error.textContent = message || "";
    error.hidden = !message;
  }

  function showOnboardingStep(step) {
    state.onboardingStep = Math.max(1, Math.min(4, step));
    $$(".wizard-step").forEach((el) => el.classList.toggle("active", Number(el.dataset.step) === state.onboardingStep));
    $$(".wizard-ruler span").forEach((el) => el.classList.toggle("active", Number(el.dataset.ruler) === state.onboardingStep));
    $("#onboarding-step-label").textContent = `Step ${state.onboardingStep} of 4`;
    $("#onboarding-progress-label").textContent = `${state.onboardingStep} / 4`;
    $("#ob-back").style.display = state.onboardingStep === 1 ? "none" : "";
    $("#ob-next").style.display = state.onboardingStep === 4 ? "none" : "";
    $("#ob-create").style.display = state.onboardingStep === 4 ? "" : "none";
    updateOnboardingPreview();
    const heading = $(".wizard-step.active .wizard-heading");
    if (heading) {
      heading.setAttribute("tabindex", "-1");
      heading.focus({ preventScroll: true });
    }
  }

  function renderOnboarding() {
    populateOnboarding();
    showOnboardingStep(state.onboardingStep);
  }

  // -----------------------------------------------------------------------
  // Inventory
  // -----------------------------------------------------------------------

  function renderInventory() {
    const q = ($("#inventory-search").value || "").toLowerCase();
    const risk = $("#inventory-risk").value;
    const chain = $("#inventory-chain").value;
    const status = $("#inventory-status").value;
    const items = state.inventory.filter((item) => {
      const haystack = `${item.product_name} ${item.template_name} ${item.address} ${item.business_owner} ${item.org_unit}`.toLowerCase();
      return (!q || haystack.includes(q)) && (!risk || item.risk_tier === risk) && (!chain || item.chain_id === chain) && (!status || item.status === status);
    });
    const rows = items.map((item) => ({
      id: item.id,
      cells: [
        `<div class="row-title">${esc(item.product_name)}</div><div class="row-sub"><span class="addr">${esc(shortAddr(item.address_eip55 || item.address))}</span> · ${esc(item.classification || "")}</div>`,
        `<div>${esc(item.template_name)}</div><div class="row-sub">v${esc(item.template_version)} · ${esc(item.category)}</div>`,
        chainPill(item.chain_name, item.environment),
        `<div>${esc(item.business_owner || "—")}</div><div class="row-sub">${esc(item.org_unit || "")}</div>`,
        riskBadge(item.risk_tier),
        auditBadge(item.template_audit_state, item.audit_days_left),
        badge(item.verification_status, item.verification_status === "exact" || item.verification_status === "match" ? "low" : item.verification_status === "partial" ? "high" : "neutral"),
        statusBadge(item.status),
      ],
    }));
    $("#inventory-table").innerHTML = table(["Contract", "Template", "Chain", "Owner / division", "Risk", "Audit", "Verification", "Status"], rows, { clickable: true, empty: "No contracts match the filters." });
    $("#inventory-count").textContent = `${items.length} of ${state.inventory.length} contracts`;
  }

  function populateInventoryChains() {
    const select = $("#inventory-chain");
    const current = select.value;
    const chains = [...new Map(state.inventory.map((item) => [item.chain_id, item.chain_name])).entries()];
    select.innerHTML = `<option value="">All chains</option>${chains.map(([id, name]) => `<option value="${esc(id)}">${esc(name)}</option>`).join("")}`;
    select.value = current;
  }

  // -----------------------------------------------------------------------
  // Templates
  // -----------------------------------------------------------------------

  function renderTemplates() {
    const q = ($("#template-search").value || "").toLowerCase();
    const category = $("#template-category").value;
    const status = $("#template-status").value;
    const items = state.templates.filter((template) => {
      const haystack = `${template.name} ${template.version} ${template.template_key} ${template.contract_type} ${(template.standards || []).map((s) => s.standard_code).join(" ")}`.toLowerCase();
      return (!q || haystack.includes(q)) && (!category || template.category === category) && (!status || template.status === status);
    });
    $("#template-grid").innerHTML = items.length ? items.map((template) => `
      <article class="template-card" data-template="${esc(template.id)}" tabindex="0" role="button">
        <div class="template-top">
          <div>
            <div class="template-name">${esc(template.name)}</div>
            <div class="template-version">v${esc(template.version)} · ${esc(template.category)}</div>
          </div>
          ${statusBadge(template.status)}
        </div>
        <div class="template-desc">${esc(template.description || "")}</div>
        <div class="mt-8">${(template.standards || []).slice(0, 4).map((s) => `<span class="chip">${esc(s.standard_code)}</span>`).join("")}</div>
        <div class="template-stats">
          <div class="template-stat"><strong>${template.deployments}</strong><span>deployments</span></div>
          <div class="template-stat"><strong>${template.chains_used}</strong><span>chains</span></div>
          <div class="template-stat"><strong>${template.live_instances || 0}</strong><span>live</span></div>
        </div>
        <div class="template-foot">
          <span>${auditBadge(template.audit_state, template.audit_days_left)}</span>
          <span>${fmtDate(template.last_deployed_at)}</span>
        </div>
      </article>`).join("") : `<div class="empty">No templates match the filters.</div>`;

    const rows = items.map((template) => ({
      cells: [
        `<div class="row-title">${esc(template.name)}</div><div class="row-sub">${esc(template.template_key)}</div>`,
        `<span class="mono">v${esc(template.version)}</span>`,
        esc(template.category),
        statusBadge(template.status),
        String(template.deployments),
        String(template.chains_used),
        auditBadge(template.audit_state, template.audit_days_left),
        esc(template.chain_names || "—"),
      ],
    }));
    $("#template-table").innerHTML = table(["Template", "Version", "Category", "Status", "Deployments", "Chains", "Audit", "Used on"], rows, { empty: "No templates." });
    $("#template-count").textContent = `${items.length} of ${state.templates.length} templates`;
  }

  function populateTemplateCategories() {
    const select = $("#template-category");
    const current = select.value;
    select.innerHTML = `<option value="">All categories</option>${state.templateMeta.categories.map((item) => `<option value="${esc(item.category)}">${esc(item.category)} (${item.count})</option>`).join("")}`;
    select.value = current;
  }

  // -----------------------------------------------------------------------
  // Approvals
  // -----------------------------------------------------------------------

  function gateRail(gates) {
    return `<div class="gate-rail">${gates.map((gate) => {
      const cls = gate.decision === "approved" ? "done" : gate.decision === "rejected" ? "rejected" : gate.is_next ? "current" : "";
      const node = gate.decision === "approved" ? "✓" : gate.decision === "rejected" ? "!" : gate.is_next ? "•" : "";
      return `<div class="gate ${cls}" title="${esc(gate.required_role)} — ${esc(gate.decision)}">
        <div class="gate-node">${node}</div>
        <div class="gate-label">${esc(gate.gate)}</div>
        <div class="gate-who">${esc(gate.decided_by_name || gate.required_role)}</div>
      </div>`;
    }).join("")}</div>`;
  }

  function approvalCard(request, kind) {
    const total = request.total_gates || request.gates.length;
    const done = request.approved_gates ?? request.gates.filter((g) => g.decision === "approved").length;
    const next = request.gates.find((g) => g.decision === "pending" && g.is_next);
    const blocked = request.readiness?.startsWith("Blocked");
    const riskTier = request.risk_tier || request.default_risk_tier;
    const title = kind === "deployment" ? request.product_name : request.product_name || request.name;
    const subtitle = kind === "deployment"
      ? `${request.id} · ${request.chain_name} · ${request.environment}`
      : kind === "change"
        ? `${request.id} · ${request.change_type} · ${request.change_ticket || "no ticket"}`
        : `${request.id} · v${request.version} · ${request.audit_status || "no audit"}`;
    return `
      <article class="approval-card">
        <div class="approval-head">
          <div>
            <div class="approval-title">${esc(title)}</div>
            <div class="approval-meta">
              <span class="mono">${esc(subtitle)}</span>
              ${riskBadge(riskTier)}
              ${statusBadge(request.status)}
              ${kind === "template" ? auditBadge(auditState(request.audit_status, request.audit_valid_until), daysLeft(request.audit_valid_until)) : ""}
              ${request.readiness ? `<span class="badge ${blocked ? "badge-critical" : "badge-neutral"}">${esc(request.readiness)}</span>` : ""}
            </div>
          </div>
          <div class="right">
            <div class="small"><strong>${done}</strong> / ${total} gates</div>
            <div class="tiny muted">${next ? `Next: ${esc(next.required_role)}` : "All gates complete"}</div>
          </div>
        </div>
        ${request.gates.length ? gateRail(request.gates) : `<div class="empty">No approval workflow has been started for this object.</div>`}
        ${progress(done, total)}
        <div class="approval-foot">
          <span class="tiny muted">${request.target_window ? `Window ${esc(request.target_window)}` : request.change_ticket ? `Ticket ${esc(request.change_ticket)}` : ""}</span>
          ${next ? `<button class="btn btn-primary btn-sm" data-gate="${esc(next.id)}">Review ${esc(next.gate)}</button>` : total === 0 ? statusBadge(request.status || "draft") : `<span class="badge badge-low">Complete</span>`}
        </div>
      </article>`;
  }

  function renderApprovals() {
    const deployments = state.approvals.deployments || [];
    const templates = state.approvals.templates || [];
    const changes = state.approvals.changes || [];
    state.approvalIndex = {};
    deployments.forEach((request) => request.gates.forEach((gate) => { state.approvalIndex[gate.id] = { kind: "deployment", request, gate }; }));
    templates.forEach((request) => request.gates.forEach((gate) => { state.approvalIndex[gate.id] = { kind: "template", request, gate }; }));
    changes.forEach((request) => request.gates.forEach((gate) => { state.approvalIndex[gate.id] = { kind: "change", request, gate }; }));

    const inReview = deployments.filter((d) => d.status === "in_review");
    const blocked = deployments.filter((d) => d.readiness?.startsWith("Blocked"));
    const pending = state.summary.counts.pending_gates;
    const approvedDeployments = deployments.filter((d) => ["approved", "deployed"].includes(d.status));
    $("#approval-kpis").innerHTML = [
      ["Deployment requests", deployments.length, `${inReview.length} in review`],
      ["Pending gates", pending, "All objects"],
      ["Blocked requests", blocked.length, "Policy or evidence gate", "alert"],
      ["Draft templates", templates.length, "Not yet approved"],
      ["Open change requests", changes.length, "Material changes"],
      ["Approved deployments", approvedDeployments.length, "Ready or live"],
    ].map(([label, value, sub, cls]) => `<div class="kpi ${cls || ""}"><div class="kpi-label">${esc(label)}</div><div class="kpi-value">${fmtNum(value)}</div><div class="kpi-sub">${esc(sub)}</div></div>`).join("");

    $("#deployment-approvals").innerHTML = deployments.length
      ? deployments.map((request) => approvalCard(request, "deployment")).join("")
      : `<div class="empty">No deployment requests.</div>`;
    $("#template-approvals").innerHTML = templates.length
      ? templates.map((request) => approvalCard(request, "template")).join("")
      : `<div class="empty">No template approvals pending.</div>`;
    $("#change-approvals").innerHTML = changes.length
      ? changes.map((request) => approvalCard(request, "change")).join("")
      : `<div class="empty">No change requests pending.</div>`;
    $("#approval-count").textContent = `${pending} pending gates`;
    $("#nav-approval-count").textContent = pending ? `(${pending})` : "";
  }

  function openApproval(gateId) {
    const entry = state.approvalIndex[gateId];
    if (!entry) return;
    const { request, gate, kind } = entry;
    const actors = gate.eligible_actors || [];
    const title = kind === "deployment" ? request.product_name : kind === "change" ? `Change · ${request.product_name}` : `${request.name} v${request.version}`;
    const detail = kind === "deployment"
      ? detailGrid([
          ["Request", esc(request.id)], ["Chain", esc(request.chain_name)], ["Environment", esc(request.environment)],
          ["Risk", riskBadge(request.risk_tier)], ["Gate", esc(gate.gate)], ["Sequence", String(gate.sequence)],
          ["Required role", esc(gate.required_role)], ["Readiness", esc(request.readiness || "—")],
        ])
      : kind === "change"
        ? detailGrid([
            ["Change", esc(request.id)], ["Contract", esc(request.product_name)], ["Type", esc(request.change_type)],
            ["Risk", riskBadge(request.risk_tier)], ["Gate", esc(gate.gate)], ["Required role", esc(gate.required_role)],
            ["Ticket", esc(request.change_ticket || "—")], ["Status", statusBadge(request.status)],
          ])
        : detailGrid([
            ["Template", esc(request.name)], ["Version", esc(request.version)], ["Status", statusBadge(request.status)],
            ["Audit", auditBadge(auditState(request.audit_status, request.audit_valid_until), daysLeft(request.audit_valid_until))], ["Gate", esc(gate.gate)], ["Required role", esc(gate.required_role)],
            ["Owner", esc(request.org_unit || "—")], ["Audit valid until", fmtDate(request.audit_valid_until)],
          ]);
    openModal(`
      <div class="modal-head">
        <div>
          <div class="eyebrow">${kind} approval</div>
          <div class="modal-title" id="modal-title">${esc(title)}</div>
          <div class="modal-sub">${esc(gate.gate)} gate · ${esc(gate.required_role)} · ${esc(request.id)}</div>
        </div>
        <button class="modal-close" data-close aria-label="Close">×</button>
      </div>
      <div class="modal-body">
        ${detail}
        <div class="form-note" style="margin-top:10px">Auth source: <strong>${esc(gate.auth_method || "seed")}</strong>. In this demo the actor comes from a selector, not an IdP. Production approvals must bind to an OIDC subject and MFA.</div>
        <div class="detail-section">
          <h4>Decision</h4>
          ${actors.length ? `
            <div class="form-row">
              <label for="actor-select">Acting as</label>
              <select id="actor-select">${actors.map((actor) => `<option value="${esc(actor.id)}">${esc(actor.display_name)} — ${esc(actor.title || actor.email)}${actor.org_unit ? ` (${esc(actor.org_unit)})` : ""}</option>`).join("")}</select>
            </div>` : `<div class="alert-item"><span class="alert-mark"></span><div class="alert-main"><div class="alert-title">No eligible actor found</div><div class="alert-sub">Assign an active ${esc(gate.required_role)} role for this scope before approving.</div></div></div>`}
          <div class="form-row">
            <label for="approval-comments">Comment / evidence reference</label>
            <textarea id="approval-comments" placeholder="Add the decision rationale or evidence reference…"></textarea>
          </div>
          <div class="form-note">Approval is checked against the role, scope, gate order and segregation of duties. The final deployment gate also checks template and audit readiness.</div>
          <div class="modal-actions">
            <button class="btn btn-danger" data-decision="rejected" ${actors.length ? "" : "disabled"}>Reject</button>
            <button class="btn btn-primary" data-decision="approved" ${actors.length ? "" : "disabled"}>Approve gate</button>
          </div>
        </div>
      </div>`);
    wireModal();
    $$("[data-decision]").forEach((button) => button.addEventListener("click", () => submitDecision(gateId, button.dataset.decision)));
  }

  async function submitDecision(gateId, decision) {
    const actor = $("#actor-select")?.value;
    const comments = $("#approval-comments")?.value || "";
    if (!actor) { toast("Select an eligible actor first.", "error"); return; }
    const buttons = $$("[data-decision]");
    buttons.forEach((b) => { b.disabled = true; });
    try {
      await api(`/api/signoffs/${encodeURIComponent(gateId)}/decision`, {
        method: "POST",
        body: JSON.stringify({ decision, actor_id: actor, comments }),
      });
      const entry = state.approvalIndex[gateId];
      const label = entry ? `${entry.gate.gate} gate for ${entry.request.id}` : "approval";
      toast(`${decision === "approved" ? "Approved" : "Rejected"} ${label}.`, decision === "approved" ? "success" : "info");
      closeModal();
      await refreshAfterAction();
    } catch (error) {
      toast(error.message, "error", 6500);
      buttons.forEach((b) => { b.disabled = false; });
    }
  }

  // -----------------------------------------------------------------------
  // Reconciliation
  // -----------------------------------------------------------------------

  function renderDiscovery() {
    const d = state.discovery;
    $("#discovery-count").textContent = `${d.queue.filter((item) => ["new", "triage", "quarantined"].includes(item.status)).length} open`;
    $("#chain-cards").innerHTML = d.chains.map((chain) => `
      <article class="chain-card">
        <div class="chain-card-head">
          <div>
            <div class="chain-name">${esc(chain.name)}</div>
            <div class="chain-meta">${esc(chain.network_type)} · ${esc(chain.environment)} · chain ${esc(chain.chain_id)}</div>
          </div>
          ${statusBadge(chain.status)}
        </div>
        <div class="chain-stats">
          <div><span>Registered</span><strong>${chain.registered_instances}</strong></div>
          <div><span>Open</span><strong>${chain.open_discoveries}</strong></div>
          <div><span>Checkpoint</span><strong>${chain.checkpoint_block ? fmtNum(chain.checkpoint_block) : "—"}</strong></div>
        </div>
        <div class="tiny muted mt-8">Last sync ${chain.last_sync_at ? fmtDateTime(chain.last_sync_at) : "never"} · ${esc(chain.last_sync_status || "no run")}</div>
      </article>`).join("");

    const queueRows = d.queue.map((item) => ({
      cells: [
        `<div class="row-title mono">${esc(shortAddr(item.address))}</div><div class="row-sub">${esc(item.classification || "Unclassified")}</div>`,
        chainPill(item.chain_name, item.environment),
        `<span class="small">${esc(item.status)}</span><div class="row-sub">${esc(item.risk_hint || "—")}</div>`,
        `<span class="small">${esc(shortAddr(item.deployer_address))}</span><div class="row-sub">Block ${fmtNum(item.block_number)}</div>`,
        `<span class="small nowrap">${fmtDate(item.first_seen_at)}</span>`,
        `<button class="btn btn-ghost btn-sm" data-discovery="${esc(item.id)}">Inspect</button>`,
      ],
    }));
    $("#discovery-table").innerHTML = table(["Address / classification", "Chain", "Status", "Deployer", "First seen", ""], queueRows, { empty: "No unknown contracts." });

    $("#sync-flow").innerHTML = [
      ["01", "Poll or subscribe", "New blocks via eth_subscribe or checkpointed eth_getBlockByNumber."],
      ["02", "Detect creation", "Transactions with no recipient; receipt provides contractAddress."],
      ["03", "Fingerprint", "Runtime code hash, init-code hash, EIP-1167 clone normalisation."],
      ["04", "Resolve proxy", "Read EIP-1967 implementation, admin and beacon slots; follow Upgraded logs."],
      ["05", "Match or queue", "Exact template match → register; unknown → triage queue and alert."],
      ["06", "Verify evidence", "Reconcile with signed deployment manifest, approvals and bytecode attestation."],
    ].map(([num, title, text]) => `
      <div class="flex gap-12" style="padding:9px 0;border-bottom:1px solid var(--line)">
        <span class="mono muted" style="min-width:22px">${num}</span>
        <div><div class="small" style="font-weight:600">${esc(title)}</div><div class="tiny muted">${esc(text)}</div></div>
      </div>`).join("") + `<div class="form-note">Private Besu groups: read receipts with the privacy group identifier, keep RPC behind mTLS/OIDC, and never expose port 8545 directly.</div>`;

    const runRows = d.runs.map((run) => ({
      cells: [
        `<span class="mono">${esc(run.id)}</span>`,
        chainPill(run.chain_name),
        esc(run.mode),
        `${fmtNum(run.from_block)} → ${fmtNum(run.to_block)}`,
        String(run.contracts_found),
        String(run.contracts_matched),
        String(run.unknown),
        statusBadge(run.status),
        `<span class="small nowrap">${fmtDateTime(run.finished_at || run.started_at)}</span>`,
      ],
    }));
    $("#sync-runs").innerHTML = table(["Run", "Chain", "Mode", "Range", "Found", "Matched", "Unknown", "Status", "Finished"], runRows, { empty: "No sync runs." });
  }

  function openDiscovery(id) {
    const item = state.discovery.queue.find((entry) => entry.id === id);
    if (!item) return;
    openModal(`
      <div class="modal-head">
        <div>
          <div class="eyebrow">Reconciliation · ${esc(item.status)}</div>
          <div class="modal-title" id="modal-title">Unregistered contract</div>
          <div class="modal-sub">${esc(item.chain_name)} · ${esc(item.id)} · first seen ${fmtDateTime(item.first_seen_at)}</div>
        </div>
        <button class="modal-close" data-close aria-label="Close">×</button>
      </div>
      <div class="modal-body">
        <div class="address-box">${esc(item.address)}<button class="copy-btn" data-copy="${esc(item.address)}">Copy</button></div>
        ${detailGrid([
          ["Chain", esc(item.chain_name)], ["Environment", esc(item.environment)], ["Block", fmtNum(item.block_number)],
          ["Status", statusBadge(item.status)], ["Risk hint", riskBadge(item.risk_hint)], ["Deployer", `<span class="mono">${esc(shortAddr(item.deployer_address))}</span>`],
          ["Suspected template", esc(item.suspected_template_name ? `${item.suspected_template_name} ${item.suspected_template_version}` : "no match")],
          ["Runtime code hash", `<span class="mono">${esc(shortHash(item.runtime_code_hash))}</span>`],
        ])}
        <div class="detail-section"><h4>Classification</h4><p class="small">${esc(item.classification || "Unclassified")}</p></div>
        <div class="detail-section"><h4>Investigation note</h4><p class="small">${esc(item.notes || "No note.")}</p></div>
        <div class="detail-section"><h4>Transaction</h4><div class="address-box">${esc(item.tx_hash || "—")}</div></div>
        <div class="modal-actions"><button class="btn btn-outline" data-close>Close</button></div>
      </div>`);
    wireModal();
  }

  // -----------------------------------------------------------------------
  // Controls
  // -----------------------------------------------------------------------

  function renderCouncil() {
    const c = state.council || {};
    const s = c.summary || {};
    $("#council-count").textContent = `${s.open_findings || 0} open findings · ${(c.personas || []).length} roles`;
    $("#council-kpis").innerHTML = [
      ["Open findings", s.open_findings || 0, `${s.remediated || 0} remediated/closed`],
      ["Critical / high open", s.critical_high_open || 0, "Need owner and due date", "alert"],
      ["Compliance profiles", `${s.compliance_complete || 0}<small> complete</small>`, `${s.compliance_partial || 0} partial · ${s.compliance_gap || 0} gap`],
      ["Approval evidence gaps", fmtNum(s.evidence_gaps || 0), "Placeholder or missing hash", "alert"],
      ["Deployer risks", s.deployer_risks || 0, "Non-allowlisted signer"],
      ["Unreconciled reserves", s.unreconciled_reserves || 0, "Bars vs snapshot"],
    ].map(([label, value, sub, cls]) => `<div class="kpi ${cls || ""}"><div class="kpi-label">${esc(label)}</div><div class="kpi-value">${value}</div><div class="kpi-sub">${esc(sub)}</div></div>`).join("");

    $("#persona-cards").innerHTML = (c.personas || []).map((p) => {
      const open = p.findings_open || 0;
      const high = p.findings_high_open || 0;
      return `<div class="alert-item" style="align-items:flex-start">
        <span class="alert-mark ${high ? "" : open ? "amber" : "green"}"></span>
        <div class="alert-main">
          <div class="flex between gap-8 center"><div class="alert-title">${esc(p.name)}</div>${badge(`${open} open`, high ? "critical" : open ? "high" : "low")}</div>
          <div class="alert-sub" style="margin-top:4px">${esc(p.mandate)}</div>
          <div class="tiny muted" style="margin-top:5px"><strong>Decision rights:</strong> ${esc(p.decision_rights)} · ${esc(p.review_cadence)}</div>
        </div>
      </div>`;
    }).join("");

    const complianceRows = (c.compliance || []).map((row) => ({
      id: row.instance_id,
      cells: [
        `<div class="row-title">${esc(row.product_name)}</div><div class="row-sub">${esc(row.legal_entity)} · ${esc(row.jurisdiction)}</div>`,
        `<div class="small">${esc(row.regulatory_classification)}</div><div class="row-sub">${esc(row.mica_type || "")}</div>`,
        riskBadge(row.aml_risk_rating),
        `<div class="small">${esc(row.sanctions_screening || "—")}</div><div class="row-sub">${esc(row.travel_rule || "")}</div>`,
        `<span class="mono tiny">${esc(row.dora_register_ref || "—")}</span>`,
        statusBadge(row.status),
        String(row.open_findings ?? 0),
      ],
    }));
    $("#compliance-table").innerHTML = table(["Product", "Classification", "AML", "Sanctions / travel rule", "DORA", "Status", "Open"], complianceRows, { clickable: true, empty: "No compliance profiles." });

    const findingRows = (c.findings || []).map((f) => ({
      cells: [
        riskBadge(f.severity),
        `<div class="row-title">${esc(f.persona_name)}</div><div class="row-sub">${esc(f.role_code)}</div>`,
        `<div class="row-title">${esc(f.title)}</div><div class="row-sub" title="${esc(f.issue)}">${esc(f.recommendation)}</div>`,
        `<div class="small">${esc(f.owner_name || "Unassigned")}</div>`,
        `<span class="small nowrap">${fmtDate(f.due_date)}</span>`,
        statusBadge(f.status),
      ],
    }));
    $("#findings-table").innerHTML = table(["Severity", "Role", "Finding / recommended action", "Owner", "Due", "Status"], findingRows, { empty: "No persona findings." });

    const gapRows = (c.evidence_gaps || []).slice(0, 10).map((g) => ({
      cells: [
        `<span class="mono">${esc(g.object_id)}</span>`,
        esc(g.gate),
        esc(g.decided_by_name || "—"),
        `<span class="badge badge-critical">${esc(g.gap)}</span>`,
      ],
    }));
    $("#evidence-gaps-table").innerHTML = table(["Object", "Gate", "Approver", "Gap"], gapRows, { empty: "No evidence gaps." })
      + `<div class="form-note" style="padding:10px 14px">Showing ${Math.min(10, (c.evidence_gaps || []).length)} of ${fmtNum((c.evidence_gaps || []).length)} approved gates with placeholder or missing evidence. This is deliberately visible, not hidden.</div>`;

    const ictRows = (c.ict || []).map((i) => ({
      cells: [
        `<div class="row-title">${esc(i.provider)}</div><div class="row-sub">${esc(i.service)}</div>`,
        riskBadge(i.criticality),
        `<span class="small">${esc(i.data_location || "—")}</span>`,
        `<span class="mono tiny">${esc(i.dora_register_ref || "—")}</span>`,
        `<span class="small">${i.linked_instances || 0} instance(s)</span>`,
      ],
    }));
    $("#ict-table").innerHTML = table(["Provider / service", "Criticality", "Data", "DORA", "Linked"], ictRows, { empty: "No ICT providers." });

    const reserveRows = (c.reserve || []).filter((r) => r.counts_toward_reserve).map((r) => ({
      cells: [
        `<div class="row-title">${esc(r.product_name)}</div><div class="row-sub">${esc(r.symbol)}</div>`,
        `<span class="small">${fmtNum(r.total_supply)}</span>`,
        `<span class="small">${fmtNum(r.token_supply)}</span>`,
        `<span class="small">${fmtNum(r.supply_delta, 4)}</span>`,
        `<span class="small">${fmtNum(r.gold_grams)} / ${fmtNum(r.bar_grams)} g</span>`,
        badge(r.bars_reconciled ? "reconciled" : "unreconciled", r.bars_reconciled ? "low" : "critical"),
      ],
    }));
    const deployerRows = (c.deployer_risk || []).map((d) => ({
      cells: [
        `<div class="row-title">${esc(d.product_name)}</div><div class="row-sub mono">${esc(shortAddr(d.address))}</div>`,
        `<div class="small">${esc(d.signing_identity || "no identity")}</div><div class="row-sub">${esc(d.key_type || "—")}</div>`,
        riskBadge(d.risk_tier),
        badge(d.allowlisted ? "allowlisted" : "not allowlisted", d.allowlisted ? "low" : "critical"),
      ],
    }));
    $("#council-recon").innerHTML = `
      <div class="detail-section" style="margin-top:0"><h4>Reserve reconciliation</h4>
        ${table(["Token", "Supply", "Snapshot supply", "Supply delta", "Gold / bar grams", "Bars"], reserveRows, { empty: "No gold reserves." })}
      </div>
      <div class="detail-section"><h4>Deployer identity</h4>
        ${table(["Contract", "Signer", "Risk", "Allowlist"], deployerRows, { empty: "All production deployers are allowlisted." })}
      </div>
      <div class="form-note">Reserve coverage is only credible when bars, snapshot and on-chain supply reconcile. Test, retired and non-reserve pools are excluded from this table; the full reconciliation remains in <code>v_reserve_reconciliation</code>.</div>`;
  }

  function renderControls() {
    const c = state.controls;
    const openIncidents = c.incidents.filter((incident) => incident.status !== "closed");
    $("#control-kpis").innerHTML = [
      ["Control pass rate", `${state.summary.control_pass_percent}<small>%</small>`, "Across applicable controls"],
      ["Exceptions", c.exceptions.length, "Accepted or remediating", "alert"],
      ["Expiring evidence", c.attestations.filter((a) => a.alert_level !== "ok").length, "Expired or next 60 days"],
      ["Open incidents", openIncidents.length, "Contained or investigating"],
      ["Reserve coverage", `${state.summary.reserve.coverage_percent.toFixed(1)}<small>%</small>`, "Attested XAU"],
      ["Audit expiring", state.templates.filter((t) => t.audit_state === "expiring").length, "Templates"],
    ].map(([label, value, sub, cls]) => `<div class="kpi ${cls || ""}"><div class="kpi-label">${esc(label)}</div><div class="kpi-value">${value}</div><div class="kpi-sub">${esc(sub)}</div></div>`).join("");

    $("#control-coverage").innerHTML = c.coverage.map((control) => {
      const applicable = control.instances_tested - (control.instances_tested - control.passing - control.exceptions - control.not_tested);
      const total = control.passing + control.exceptions + control.not_tested;
      const pct = total ? Math.round((control.passing / total) * 100) : 0;
      return `<div class="control-row">
        <div class="control-top"><strong>${esc(control.code)} · ${esc(control.name)}</strong><span>${control.passing}/${total} · ${pct}%</span></div>
        <div class="bar-track"><div class="bar-fill ${pct >= 90 ? "green" : pct >= 70 ? "amber" : ""}" style="width:${pct}%"></div></div>
      </div>`;
    }).join("");

    const attRows = c.attestations.map((a) => ({
      cells: [
        `<div class="row-title">${esc(a.subject)}</div><div class="row-sub">${esc(a.attestation_type.replaceAll("_", " "))}</div>`,
        esc(a.provider),
        `<span class="small">${fmtDate(a.expires_at)}</span><div class="row-sub">${a.days_left} days</div>`,
        badge(a.alert_level, a.alert_level === "expired" ? "critical" : a.alert_level === "critical" ? "critical" : "high"),
      ],
    }));
    $("#attestation-table").innerHTML = table(["Evidence", "Provider", "Expires", "Level"], attRows, { empty: "No expiring evidence." });

    const exRows = c.exceptions.map((item) => ({
      cells: [
        `<div class="row-title">${esc(item.product_name)}</div><div class="row-sub">${esc(item.control_code)} · ${esc(item.control_name)}</div>`,
        statusBadge(item.status),
        `<span class="small">${esc(item.exception_approver || "unassigned")}</span>`,
        `<span class="small">${fmtDate(item.next_test_due)}</span>`,
      ],
    }));
    $("#control-exceptions").innerHTML = table(["Exception", "Status", "Accepted by", "Next test"], exRows, { empty: "No exceptions." });

    const incRows = openIncidents.map((incident) => ({
      cells: [
        `<div class="row-title">${esc(incident.title)}</div><div class="row-sub">${esc(incident.id)} · ${fmtDate(incident.opened_at)}</div>`,
        riskBadge(incident.severity),
        statusBadge(incident.status),
      ],
    }));
    $("#incident-table").innerHTML = table(["Incident", "Severity", "Status"], incRows, { empty: "No open incidents." });

    const reserveRows = c.reserve.map((row) => ({
      cells: [
        `<div class="row-title">${esc(row.product_name)}</div><div class="row-sub">${esc(row.symbol)} · ${esc(row.reserve_pool || "no pool")}</div>`,
        `<span class="small">${fmtNum(row.total_supply)}</span>`,
        `<span class="small">${fmtNum(row.gold_grams)} g</span>`,
        `<span class="badge ${row.reserve_state === "current" ? "badge-low" : "badge-critical"}">${row.reserve_state}</span>`,
        row.counts_toward_reserve ? "Yes" : "No",
      ],
    }));
    $("#reserve-table").innerHTML = table(["Token", "Supply", "Gold", "Reserve", "Counts?"], reserveRows, { empty: "No token reserves." });

    const readinessRows = c.readiness.map((row) => ({
      cells: [
        `<span class="mono">${esc(row.id)}</span>`,
        statusBadge(row.request_status),
        statusBadge(row.template_status),
        auditBadge(auditState(row.audit_status, row.audit_valid_until), daysLeft(row.audit_valid_until)),
        `<span class="small">${esc(row.readiness)}</span>`,
        String(row.pending_blocking_gates),
      ],
    }));
    $("#readiness-table").innerHTML = table(["Request", "Request status", "Template", "Audit", "Readiness", "Pending"], readinessRows, { empty: "No deployment requests." });
    $("#control-count").textContent = `${c.coverage.length} controls · ${c.exceptions.length} exceptions`;
  }

  // -----------------------------------------------------------------------
  // Contract detail modal
  // -----------------------------------------------------------------------

  async function openContract(id) {
    try {
      const d = await api(`/api/contracts/${encodeURIComponent(id)}`);
      const token = d.token || {};
      const reserve = d.reserve || {};
      const template = d.template || {};
      const compliance = d.compliance || {};
      const signer = d.signer || {};
      const tabs = [
        ["summary", "Summary"],
        ["compliance", "Compliance"],
        ["dependencies", `Dependencies (${(d.links || []).length})`],
        ["governance", "Governance"],
        ["evidence", "Evidence"],
        ["onchain", "On-chain"],
        ["changes", "Changes & incidents"],
      ];
      openModal(`
        <div class="modal-head">
          <div>
            <div class="eyebrow">${esc(d.chain_name)} · ${esc(d.instance_kind)}</div>
            <div class="modal-title" id="modal-title">${esc(d.product_name || d.id)}</div>
            <div class="modal-sub">${esc(template.name || "")} v${esc(template.version || "")} · ${esc(d.business_owner || "no owner")} · ${esc(d.org_unit || "")}</div>
            <div class="flex gap-8 mt-8">${riskBadge(d.risk_tier)} ${statusBadge(d.status)} ${auditBadge(auditState(template.audit_status, template.audit_valid_until), daysLeft(template.audit_valid_until))} ${badge(d.verification_status, d.verification_status === "exact" ? "low" : "high")}</div>
          </div>
          <button class="modal-close" data-close aria-label="Close">×</button>
        </div>
        <div class="modal-body">
          <div class="address-box">${esc(d.address_eip55 || d.address)}<button class="copy-btn" data-copy="${esc(d.address)}">Copy</button></div>
          <div class="modal-tabs" role="tablist">${tabs.map(([key, label], index) => `<button class="modal-tab ${index === 0 ? "active" : ""}" data-panel="panel-${key}">${esc(label)}</button>`).join("")}</div>
          <div class="modal-panel active" id="panel-summary">
            ${detailGrid([
              ["Template", `${esc(template.name)} <span class="mono">v${esc(template.version)}</span>`],
              ["Category", esc(template.category || "—")],
              ["Business owner", esc(d.business_owner || "—")],
              ["Division", esc(d.division || d.org_unit || "—")],
              ["Legal entity", esc(d.legal_entity || "—")],
              ["Jurisdiction", esc(d.jurisdiction || "—")],
              ["Classification", esc(d.classification || "—")],
              ["Privacy group", esc(d.privacy_group || "public / none")],
              ["Deployed", fmtDateTime(d.deployed_at)],
              ["Block", fmtNum(d.block_number)],
              ["Proxy", esc(d.proxy_type || "none")],
              ["Implementation", d.implementation_address ? `<span class="mono">${esc(shortAddr(d.implementation_address))}</span>` : "—"],
              ["Admin", d.admin_address ? `<span class="mono">${esc(shortAddr(d.admin_address))}</span>` : "—"],
              ["Verification", esc(d.verification_provider || "—")],
              ["Criticality", esc(d.criticality || "—")],
              ["Deployment request", esc(d.deployment_request_id || "backfilled / none")],
              ["Signer identity", d.signer_identity ? `${esc(d.signer_identity)} · ${esc(d.signer_key_type)} ${badge(d.signer_allowlisted ? "allowlisted" : "not allowlisted", d.signer_allowlisted ? "low" : "critical")}` : "—"],
              ["Compliance profile", d.compliance?.status ? statusBadge(d.compliance.status) : badge("not recorded", "critical")],
            ])}
            ${token.symbol ? `<div class="detail-section"><h4>Token & reserve</h4>${detailGrid([
              ["Token", `${esc(token.token_name)} (${esc(token.symbol)})`], ["Supply", fmtNum(token.total_supply)],
              ["Asset", esc(token.underlying_asset || token.asset_class)], ["Custodian", esc(token.custodian || "—")],
              ["Reserve pool", esc(reserve.reserve_pool || "—")], ["Coverage", reserve.coverage_ratio ? `${(reserve.coverage_ratio * 100).toFixed(2)}%` : "—"],
              ["Bars", reserve.bars_count ?? "—"], ["Counts toward reserve", token.counts_toward_reserve ? "Yes" : "No"],
            ])}</div>` : ""}
            <div class="detail-section"><h4>Parameters</h4>${d.parameters.length ? table(["Parameter", "Value", "Template default", "Source"], d.parameters.map((p) => ({ cells: [
              `<span class="mono">${esc(p.name)}</span>`,
              esc(p.value ?? "—"),
              esc(p.default_value ?? "—"),
              esc(p.source),
            ] }))) : `<div class="empty">No captured parameters.</div>`}</div>
          </div>
          <div class="modal-panel" id="panel-compliance">
            ${compliance.regulatory_classification ? `
              ${detailGrid([
                ["Regulatory classification", esc(compliance.regulatory_classification)],
                ["MiCA / regime", esc(compliance.mica_type || "—")],
                ["Instrument / fungibility", `${esc(compliance.instrument_id || "—")} · ${esc(compliance.fungibility_group || "—")}`],
                ["Prospectus / terms", esc(compliance.prospectus_ref || "—")],
                ["AML risk", riskBadge(compliance.aml_risk_rating)],
                ["Client eligibility", esc(compliance.client_eligibility || "—")],
                ["Sanctions screening", esc(compliance.sanctions_screening || "—")],
                ["Travel rule", esc(compliance.travel_rule || "—")],
                ["Distribution countries", esc(compliance.distribution_countries || "—")],
                ["Investor type", esc(compliance.investor_type || "—")],
                ["Legal structure", esc(compliance.legal_structure || "—")],
                ["Holder claim", esc(compliance.holder_claim_type || "—")],
                ["Custody agreement", esc(compliance.custody_agreement_ref || "—")],
                ["Legal title", esc(compliance.legal_title_ref || "—")],
                ["Segregation", esc(compliance.segregation_basis || "—")],
                ["Insolvency remoteness", esc(compliance.insolvency_remoteness || "—")],
                ["DPIA", esc(compliance.dpia_ref || "—")],
                ["DPO assessment", esc(compliance.dpo_assessment || "—")],
                ["On-chain PII", esc(compliance.onchain_pii_risk || "—")],
                ["Privacy-group members", esc(compliance.privacy_group_members || "—")],
                ["DORA reference", esc(compliance.dora_register_ref || "—")],
                ["ICT third parties", esc(compliance.ict_third_party_ref || "—")],
                ["Exit plan", esc(compliance.exit_plan || "—")],
                ["Redemption", `${esc(compliance.redemption_rights || "—")} · ${esc(compliance.redemption_sla || "—")}`],
                ["Complaints / redress", esc(compliance.complaint_handling || "—")],
                ["Records retention", esc(compliance.records_retention || "—")],
                ["Tax treatment", esc(compliance.tax_treatment || "—")],
                ["Profile status", `${statusBadge(compliance.status)} · reviewed ${fmtDate(compliance.last_reviewed_at)} by ${esc(compliance.reviewed_by_name || "—")}`],
              ])}
              <div class="detail-section"><h4>ICT dependencies</h4>${d.ict.length ? table(["Provider / service", "Criticality", "Data", "DORA"], d.ict.map((i) => ({ cells: [
                `<div class="row-title">${esc(i.provider)}</div><div class="row-sub">${esc(i.service)} · ${esc(i.dependency_type)}</div>`,
                riskBadge(i.criticality),
                esc(i.data_location || "—"),
                esc(i.dora_register_ref || "—"),
              ] }))) : `<div class="empty">No ICT links.</div>`}</div>
              <div class="detail-section"><h4>Signing identity</h4>${signer.name ? detailGrid([
                ["Signer", esc(signer.name)],
                ["Key type", esc(signer.key_type)],
                ["Provider", esc(signer.provider || "—")],
                ["Owner", esc(signer.owner_name || "—")],
                ["Allowlisted", badge(signer.allowlisted ? "yes" : "no", signer.allowlisted ? "low" : "critical")],
                ["Valid", `${fmtDate(signer.valid_from)} → ${signer.valid_to ? fmtDate(signer.valid_to) : "open"}`],
              ]) : `<div class="empty">No signing identity recorded.</div>`}</div>
            ` : `<div class="empty">No compliance profile recorded. This is a control gap.</div>`}
          </div>
          <div class="modal-panel" id="panel-dependencies">
            <div class="detail-section"><h4>Dependency graph</h4>
              <div class="link-list">${(d.links || []).map((link) => {
                const outbound = link.from_id === d.id;
                const target = outbound ? link.to_name : link.from_name;
                const targetId = outbound ? link.to_id : link.from_id;
                return `<div class="link-item"><span class="link-relation">${esc(link.relation.replaceAll("_", " "))}</span><span class="link-arrow">${outbound ? "→" : "←"}</span><button class="card-link" data-contract="${esc(targetId)}">${esc(target || targetId)}</button><span class="tiny muted">${esc(link.confidence)}</span></div>`;
              }).join("") || `<div class="empty">No linked contracts.</div>`}</div>
            </div>
            <div class="detail-section"><h4>Roles</h4>${d.roles.length ? table(["Role", "Holder", "Type", "Status"], d.roles.map((r) => ({ cells: [
              `<span class="mono">${esc(r.role_name)}</span>`,
              `<span class="mono">${esc(shortAddr(r.holder_address))}</span>`,
              esc(r.holder_type),
              statusBadge(r.status),
            ] }))) : `<div class="empty">No role data.</div>`}</div>
          </div>
          <div class="modal-panel" id="panel-governance">
            <div class="detail-section"><h4>Privileged roles</h4>${d.roles.length ? table(["Role", "Holder", "Type", "Assigned"], d.roles.map((r) => ({ cells: [
              `<span class="mono">${esc(r.role_name)}</span>`,
              `<span class="mono">${esc(shortAddr(r.holder_address))}</span>`,
              esc(r.holder_type),
              fmtDate(r.assigned_at),
            ] }))) : `<div class="empty">No role data.</div>`}</div>
            <div class="detail-section"><h4>Control tests</h4>${d.controls.length ? table(["Control", "Status", "Last tested", "Note"], d.controls.map((c) => ({ cells: [
              `${esc(c.code)} · ${esc(c.name)}`,
              statusBadge(c.status === "pass" ? "valid" : c.status === "exception" || c.status === "fail" ? "expired" : "pending"),
              fmtDate(c.last_tested_at),
              esc(c.notes || "—"),
            ] }))) : `<div class="empty">No control tests.</div>`}</div>
          </div>
          <div class="modal-panel" id="panel-evidence">
            <div class="detail-section"><h4>Documents</h4>${d.documents.length ? table(["Document", "Type", "Version", "Hash", "Valid to"], d.documents.map((doc) => ({ cells: [
              `<div class="row-title">${esc(doc.title)}</div><div class="row-sub">${esc(doc.uri)}</div>`,
              esc(doc.doc_type.replaceAll("_", " ")),
              esc(doc.version || "—"),
              `<span class="mono">${esc(shortHash(doc.sha256))}</span>`,
              fmtDate(doc.valid_to),
            ] }))) : `<div class="empty">No documents linked.</div>`}</div>
            <div class="detail-section"><h4>Attestations</h4>${d.attestations.length ? table(["Attestation", "Provider", "Result", "Expires", "Status"], d.attestations.map((a) => ({ cells: [
              esc(a.attestation_type.replaceAll("_", " ")),
              esc(a.provider),
              esc(a.result),
              fmtDate(a.expires_at),
              statusBadge(a.status),
            ] }))) : `<div class="empty">No attestations.</div>`}</div>
          </div>
          <div class="modal-panel" id="panel-onchain">
            <div class="detail-section"><h4>On-chain events</h4>${d.events.length ? `<div class="timeline">${d.events.map((event) => `<div class="timeline-item"><div class="timeline-date">${fmtDateTime(event.observed_at)} · block ${fmtNum(event.block_number)}</div><div class="timeline-title">${esc(event.event_name)}</div><div class="timeline-sub">${esc(event.signature || "")} · <span class="mono">${esc(shortHash(event.tx_hash))}</span></div><div class="timeline-sub mono">${esc(event.payload_json || "")}</div></div>`).join("")}</div>` : `<div class="empty">No indexed events.</div>`}</div>
            ${reserve.snapshot_id ? `<div class="detail-section"><h4>Reserve snapshot</h4>${detailGrid([
              ["As of", fmtDate(reserve.as_of)], ["Supply", fmtNum(reserve.token_supply)],
              ["Gold", `${fmtNum(reserve.gold_grams)} g`], ["Coverage", `${(reserve.coverage_ratio * 100).toFixed(2)}%`],
              ["Auditor", esc(reserve.auditor)], ["Bars", reserve.bars_count],
            ])}</div>` : ""}
          </div>
          <div class="modal-panel" id="panel-changes">
            <div class="detail-section"><h4>Change requests</h4>${d.changes.length ? table(["Change", "Type", "Status", "Risk", "Ticket"], d.changes.map((c) => ({ cells: [
              `<div class="row-title">${esc(c.id)}</div><div class="row-sub">${esc(c.description)}</div>`,
              esc(c.change_type), statusBadge(c.status), riskBadge(c.risk_tier), esc(c.change_ticket || "—"),
            ] }))) : `<div class="empty">No change requests.</div>`}</div>
            <div class="detail-section"><h4>Incidents</h4>${d.incidents.length ? table(["Incident", "Severity", "Status", "Opened"], d.incidents.map((i) => ({ cells: [
              `<div class="row-title">${esc(i.title)}</div><div class="row-sub">${esc(i.id)}</div>`,
              riskBadge(i.severity), statusBadge(i.status), fmtDate(i.opened_at),
            ] }))) : `<div class="empty">No incidents.</div>`}</div>
            <div class="detail-section"><h4>Deployment sign-offs</h4>${d.signoffs.length ? table(["Gate", "Role", "Decision", "By", "Auth", "Date"], d.signoffs.map((s) => ({ cells: [
              esc(s.gate), esc(s.required_role), statusBadge(s.decision), esc(s.decided_by_name || "—"), esc(s.auth_method || "—"), fmtDate(s.decided_at),
            ] }))) : `<div class="empty">No linked deployment request.</div>`}</div>
          </div>
        </div>`);
      wireModal();
      $$("[data-contract]", $("#modal-content")).forEach((el) => el.addEventListener("click", (event) => {
        event.stopPropagation();
        openContract(el.dataset.contract);
      }));
    } catch (error) {
      toast(error.message, "error");
    }
  }

  // -----------------------------------------------------------------------
  // Template detail modal
  // -----------------------------------------------------------------------

  async function openTemplate(id) {
    try {
      const d = await api(`/api/templates/${encodeURIComponent(id)}`);
      const tabs = [["overview", "Overview"], ["deployments", `Deployments (${d.instances.length})`], ["standards", "Standards"], ["evidence", "Evidence"], ["parameters", "Parameters"]];
      openModal(`
        <div class="modal-head">
          <div>
            <div class="eyebrow">Template · ${esc(d.category)}</div>
            <div class="modal-title" id="modal-title">${esc(d.name)} <span class="muted" style="font-size:16px">v${esc(d.version)}</span></div>
            <div class="modal-sub">${esc(d.template_key)} · ${esc(d.contract_type)} · owner ${esc(d.org_unit || "—")}</div>
            <div class="flex gap-8 mt-8">${statusBadge(d.status)} ${auditBadge(d.audit_state, d.audit_days_left)} ${riskBadge(d.default_risk_tier)} ${badge(`${d.deployments} deployments`, "neutral")}</div>
          </div>
          <button class="modal-close" data-close aria-label="Close">×</button>
        </div>
        <div class="modal-body">
          <div class="modal-tabs" role="tablist">${tabs.map(([key, label], index) => `<button class="modal-tab ${index === 0 ? "active" : ""}" data-panel="panel-${key}">${esc(label)}</button>`).join("")}</div>
          <div class="modal-panel active" id="panel-overview">
            <p class="small">${esc(d.description || "")}</p>
            <div class="detail-section">${detailGrid([
              ["Version", esc(d.version)], ["Status", statusBadge(d.status)], ["Category", esc(d.category)],
              ["Contract type", esc(d.contract_type)], ["Compiler", esc(d.compiler_version || "—")], ["EVM", esc(d.evm_version || "—")],
              ["Licence", esc(d.license || "—")], ["Audit", `${esc(d.audit_provider || "—")} · ${fmtDate(d.audit_valid_until)}`],
              ["Runtime hash", `<span class="mono">${esc(shortHash(d.runtime_code_hash))}</span>`], ["Init hash", `<span class="mono">${esc(shortHash(d.initcode_hash))}</span>`],
              ["Approved", fmtDate(d.approved_at)], ["Created", fmtDate(d.created_at)],
            ])}</div>
            <div class="detail-section"><h4>Dependencies</h4>${d.dependencies.length ? `<div class="link-list">${d.dependencies.map((dep) => `<div class="link-item"><span class="link-relation">${esc(dep.relation.replaceAll("_", " "))}</span><button class="card-link" data-template="${esc(dep.id)}">${esc(dep.name)} v${esc(dep.version)}</button><span class="tiny muted">${esc(dep.status)}</span></div>`).join("")}</div>` : `<div class="empty">No template dependencies.</div>`}</div>
            <div class="detail-section"><h4>Software inventory</h4>${d.used_by_ci.length ? table(["CI", "Lifecycle", "Criticality"], d.used_by_ci.map((ci) => ({ cells: [esc(ci.ci_name), esc(ci.lifecycle_status), riskBadge(ci.criticality)] }))) : `<div class="empty">No CMDB link.</div>`}</div>
          </div>
          <div class="modal-panel" id="panel-deployments">
            ${d.instances.length ? table(["Contract", "Chain", "Status", "Risk", "Deployed"], d.instances.map((ci) => ({ cells: [
              `<button class="card-link" data-contract="${esc(ci.id)}">${esc(ci.product_name)}</button><div class="row-sub mono">${esc(shortAddr(ci.address))}</div>`,
              esc(ci.chain_name), statusBadge(ci.status), riskBadge(ci.risk_tier), fmtDate(ci.deployed_at),
            ] }))) : `<div class="empty">No deployments from this template.</div>`}
          </div>
          <div class="modal-panel" id="panel-standards">
            ${d.standards.length ? table(["Standard", "Family", "Conformance", "Note"], d.standards.map((s) => ({ cells: [
              `<span class="mono">${esc(s.standard_code)}</span>`, esc(s.family), esc(s.conformance), esc(s.notes || "—"),
            ] }))) : `<div class="empty">No standards mapped.</div>`}
          </div>
          <div class="modal-panel" id="panel-evidence">
            <div class="detail-section"><h4>Attestations</h4>${d.attestations.length ? table(["Type", "Provider", "Result", "Expires", "Status"], d.attestations.map((a) => ({ cells: [esc(a.attestation_type.replaceAll("_", " ")), esc(a.provider), esc(a.result), fmtDate(a.expires_at), statusBadge(a.status)] }))) : `<div class="empty">No attestations.</div>`}</div>
            <div class="detail-section"><h4>Documents</h4>${d.documents.length ? table(["Document", "Type", "Version", "Hash"], d.documents.map((doc) => ({ cells: [`<div class="row-title">${esc(doc.title)}</div><div class="row-sub">${esc(doc.uri)}</div>`, esc(doc.doc_type), esc(doc.version || "—"), `<span class="mono">${esc(shortHash(doc.sha256))}</span>`] }))) : `<div class="empty">No documents.</div>`}</div>
            <div class="detail-section"><h4>Template sign-offs</h4>${d.signoffs.length ? table(["Gate", "Role", "Decision", "By", "Date"], d.signoffs.map((s) => ({ cells: [esc(s.gate), esc(s.required_role), statusBadge(s.decision), esc(s.decided_by_name || "—"), fmtDate(s.decided_at)] }))) : `<div class="empty">No approval workflow.</div>`}</div>
          </div>
          <div class="modal-panel" id="panel-parameters">
            ${d.parameters.length ? table(["Parameter", "Type", "Required", "Default", "Description"], d.parameters.map((p) => ({ cells: [
              `<span class="mono">${esc(p.name)}</span>`, esc(p.data_type), p.required ? "Yes" : "No", esc(p.default_value || "—"), esc(p.description || "—"),
            ] }))) : `<div class="empty">No parameters.</div>`}
          </div>
        </div>`);
      wireModal();
      $$("[data-contract]", $("#modal-content")).forEach((el) => el.addEventListener("click", () => openContract(el.dataset.contract)));
      $$("[data-template]", $("#modal-content")).forEach((el) => el.addEventListener("click", () => openTemplate(el.dataset.template)));
    } catch (error) {
      toast(error.message, "error");
    }
  }

  // -----------------------------------------------------------------------
  // Refresh / bootstrap
  // -----------------------------------------------------------------------

  async function loadAll() {
    const [summary, inventory, templates, approvals, discovery, controls, council, registration, reference] = await Promise.all([
      api("/api/summary"),
      api("/api/contracts"),
      api("/api/templates"),
      api("/api/approvals"),
      api("/api/discovery"),
      api("/api/controls"),
      api("/api/council"),
      api("/api/registrations"),
      api("/api/reference"),
    ]);
    state.summary = summary;
    state.inventory = inventory.items || [];
    state.templates = templates.items || [];
    state.templateMeta = templates.meta || { categories: [], risk: [] };
    state.approvals = approvals;
    state.discovery = discovery;
    state.controls = controls;
    state.council = council;
    state.registration = registration;
    state.reference = reference;
    state.loading = false;
    populateInventoryChains();
    populateTemplateCategories();
    renderAll();
  }

  async function refreshAfterAction() {
    await loadAll();
    switchView(state.view, false);
  }

  function renderAll() {
    if (!state.summary) return;
    renderOverview();
    renderRegistration();
    renderOnboarding();
    renderInventory();
    renderTemplates();
    renderApprovals();
    renderDiscovery();
    renderControls();
    renderCouncil();
    switchView(state.view, false);
  }

  async function runSync() {
    const button = $("#sync-btn");
    const original = button.textContent;
    button.disabled = true;
    button.textContent = "Syncing…";
    try {
      const result = await api("/api/sync", { method: "POST", body: JSON.stringify({ chain_id: "ch-besu-prod" }) });
      toast(`Besu sync completed: ${result.discovered || 0} new contract(s), ${result.matched || 0} matched.`, "success");
      const [summary, discovery] = await Promise.all([api("/api/summary"), api("/api/discovery")]);
      state.summary = summary;
      state.discovery = discovery;
      renderOverview();
      renderDiscovery();
    } catch (error) {
      toast(error.message, error.status === 404 ? "info" : "error");
    } finally {
      button.disabled = false;
      button.textContent = original;
    }
  }

  function exportRegister() {
    const payload = {
      generated_at: new Date().toISOString(),
      summary: state.summary,
      inventory: state.inventory,
      templates: state.templates,
      approvals: state.approvals,
      discovery: state.discovery,
      controls: state.controls,
      council: state.council,
      registration: state.registration,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = "smart-contract-register.json";
    anchor.click();
    URL.revokeObjectURL(url);
    toast("Register exported as JSON.", "success");
  }

  // -----------------------------------------------------------------------
  // Events
  // -----------------------------------------------------------------------

  document.addEventListener("click", (event) => {
    const nav = event.target.closest("[data-view], [data-nav]");
    if (nav) {
      switchView(nav.dataset.view || nav.dataset.nav);
      return;
    }
    const registration = event.target.closest("[data-registration]");
    if (registration) {
      event.preventDefault();
      state.selectedRegistration = registration.dataset.registration;
      renderRegistration();
      switchView("registration", false);
      return;
    }
    const contract = event.target.closest("[data-contract]");
    if (contract && !event.target.closest("[data-template]")) {
      event.preventDefault();
      openContract(contract.dataset.contract);
      return;
    }
    const template = event.target.closest("[data-template]");
    if (template) {
      event.preventDefault();
      openTemplate(template.dataset.template);
      return;
    }
    const gate = event.target.closest("[data-gate]");
    if (gate) {
      event.preventDefault();
      openApproval(gate.dataset.gate);
      return;
    }
    const discovery = event.target.closest("[data-discovery]");
    if (discovery) {
      event.preventDefault();
      openDiscovery(discovery.dataset.discovery);
      return;
    }
    const approvalRequest = event.target.closest("[data-approval-request]");
    if (approvalRequest) {
      const request = (state.approvals.deployments || []).find((item) => item.id === approvalRequest.dataset.approvalRequest);
      const next = request?.gates.find((g) => g.decision === "pending" && g.is_next);
      if (next) openApproval(next.id);
      else switchView("approvals");
    }
  });

  async function submitOnboarding() {
    const values = onboardingValues();
    if (!values.contract_name) {
      setNameError("Contract / product name is required.");
      showOnboardingStep(1);
      $("#ob-name").focus();
      return;
    }
    setNameError("");
    if (values.risk_below_floor) {
      toast(`Risk tier is below the policy minimum (${values.policy_risk}).`, "error", 7000);
      showOnboardingStep(2);
      $("#ob-risk").focus();
      return;
    }
    if (values.code_source === "approved_params" && !values.template_id) {
      toast("Choose the approved template you are reusing.", "error");
      showOnboardingStep(1);
      return;
    }
    const button = $("#ob-create");
    button.disabled = true;
    button.textContent = "Creating…";
    try {
      const result = await api("/api/onboarding", {
        method: "POST",
        body: JSON.stringify(values),
      });
      const gaps = result.missing_evidence?.length || 0;
      toast(`Created ${result.request_id} · ${gaps} evidence gap(s) · pre-chain only.`, gaps ? "info" : "success", 6500);
      state.selectedRegistration = result.request_id;
      state.onboardingStep = 1;
      await loadAll();
      switchView("registration");
    } catch (error) {
      toast(error.message, "error", 7000);
    } finally {
      button.disabled = false;
      button.textContent = "Create pre-chain registration";
    }
  }

  $("#ob-name").addEventListener("input", () => setNameError(""));
  $("#ob-source").addEventListener("change", () => {
    $("#ob-template-row").style.display = $("#ob-source").value === "approved_params" ? "" : "none";
    updateOnboardingPreview();
  });
  $$("#onboarding-form input, #onboarding-form select, #onboarding-form textarea").forEach((el) => {
    el.addEventListener("change", updateOnboardingPreview);
    el.addEventListener("input", updateOnboardingPreview);
  });
  $("#ob-next").addEventListener("click", () => {
    if (state.onboardingStep === 1 && !onboardingValues().contract_name) {
      setNameError("Give the contract a name first.");
      $("#ob-name").focus();
      return;
    }
    if (state.onboardingStep === 1) setNameError("");
    if (state.onboardingStep === 1 && $("#ob-source").value === "approved_params" && !$("#ob-template").value) {
      toast("Choose an approved template.", "error");
      return;
    }
    showOnboardingStep(state.onboardingStep + 1);
  });
  $("#ob-back").addEventListener("click", () => showOnboardingStep(state.onboardingStep - 1));
  $("#ob-create").addEventListener("click", submitOnboarding);

  $("#registration-new").addEventListener("click", () => switchView("onboarding"));
  $("#inventory-search").addEventListener("input", renderInventory);
  $("#inventory-risk").addEventListener("change", renderInventory);
  $("#inventory-chain").addEventListener("change", renderInventory);
  $("#inventory-status").addEventListener("change", renderInventory);
  $("#template-search").addEventListener("input", renderTemplates);
  $("#template-category").addEventListener("change", renderTemplates);
  $("#template-status").addEventListener("change", renderTemplates);
  $("#export-btn").addEventListener("click", exportRegister);
  $("#sync-btn").addEventListener("click", runSync);

  $("#modal-backdrop").addEventListener("click", (event) => {
    if (event.target === $("#modal-backdrop")) closeModal();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeModal();
    if ($("#modal-backdrop").classList.contains("open") && event.key === "Tab") {
      const focusable = $$("button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])", $("#modal")).filter((el) => !el.disabled && el.offsetParent !== null);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
    if ((event.key === "Enter" || event.key === " ") && !event.target.closest("input, textarea, select, button, a")) {
      const row = event.target.closest("tr[data-contract], tr[data-registration]");
      if (row) {
        event.preventDefault();
        row.click();
        return;
      }
      const card = event.target.closest(".template-card[data-template]");
      if (card) {
        event.preventDefault();
        openTemplate(card.dataset.template);
      }
    }
  });

  // -----------------------------------------------------------------------
  // Platform tour
  // -----------------------------------------------------------------------

  const TOUR_STEPS = [
    {
      view: "overview", center: true,
      title: "Why this platform exists",
      body: "Teams use different records. The bank cannot link an approval to an address. This platform keeps one controlled record.",
    },
    {
      view: "overview", target: "#kpi-grid", placement: "bottom",
      title: "Read the signals",
      body: "The Overview shows six measures. It shows the approval queue and the attention list. Use it to find blocked work.",
    },
    {
      view: "overview", target: '[data-view="onboarding"]', placement: "bottom",
      title: "Start at Onboarding",
      body: "Select Onboarding to register a contract. Do this before deployment. The record starts with the business intent.",
    },
    {
      view: "onboarding", target: "#ob-purpose", placement: "bottom",
      title: "Answer the four steps",
      body: "Select the purpose, code source, chain, users, risk, and deployment authority. The platform calculates the required gates.",
    },
    {
      view: "onboarding", target: "#onboarding-preview", placement: "bottom",
      title: "Review risk and evidence",
      body: "The preview shows the policy minimum, the gate count, and the missing evidence. Do not select a risk tier below the policy minimum.",
    },
    {
      view: "registration", target: "#registration-receipt", placement: "bottom",
      title: "The record is pre-chain",
      body: "The new registration has no address and no transaction. It has a request ID, a template, a config hash, and a manifest hash.",
    },
    {
      view: "approvals", target: "#approval-kpis", placement: "bottom",
      title: "Approve in order",
      body: "Approvers work in order. The requester cannot approve. One person cannot approve two blocking gates on the same object.",
    },
    {
      view: "registration", target: "#registration-table", placement: "top",
      title: "Link the on-chain record",
      body: "After FireFly and Kaleido deploy, Registration shows the address, transaction, block, and runtime hash. A hash match confirms the link.",
    },
    {
      view: "council", target: "#council-kpis", placement: "bottom",
      title: "Review the gaps",
      body: "Council shows the findings and the evidence gaps. Controls shows the control tests and the exceptions. Do not hide a gap.",
    },
    {
      view: "overview", center: true,
      title: "Start now",
      body: "Select Onboarding to start a registration. Select Platform tour to repeat this guide.",
    },
  ];

  let tourIndex = 0;
  let tourActive = false;
  let tourBusy = false;
  const tourLayer = $("#tour-layer");
  const tourPopover = $("#tour-popover");
  const tourSpotlight = $("#tour-spotlight");

  function tourWait(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function positionTour(step) {
    const target = step.target ? $(step.target) : null;
    if (step.center || !target) {
      tourSpotlight.classList.add("center");
      tourSpotlight.style.width = "1px";
      tourSpotlight.style.height = "1px";
      tourSpotlight.style.left = "50%";
      tourSpotlight.style.top = "50%";
      tourPopover.classList.add("center");
      tourPopover.dataset.placement = "center";
      tourPopover.style.left = "";
      tourPopover.style.top = "";
      tourPopover.style.removeProperty("--arrow-left");
      return;
    }
    tourSpotlight.classList.remove("center");
    tourPopover.classList.remove("center");
    const rect = target.getBoundingClientRect();
    const width = tourPopover.offsetWidth;
    const height = tourPopover.offsetHeight;
    const margin = 14;
    let placement = step.placement || "bottom";
    if (placement === "bottom" && rect.bottom + height + margin > window.innerHeight - 12) placement = "top";
    if (placement === "top" && rect.top - height - margin < 12) placement = "bottom";
    const left = Math.max(12, Math.min(rect.left + rect.width / 2 - width / 2, window.innerWidth - width - 12));
    let top;
    if (placement === "top") top = Math.max(12, rect.top - height - margin);
    else top = Math.min(rect.bottom + margin, window.innerHeight - height - 12);
    tourSpotlight.style.left = `${Math.max(6, rect.left - 6)}px`;
    tourSpotlight.style.top = `${Math.max(6, rect.top - 6)}px`;
    tourSpotlight.style.width = `${Math.min(window.innerWidth - 12, rect.width + 12)}px`;
    tourSpotlight.style.height = `${Math.min(window.innerHeight - 12, rect.height + 12)}px`;
    if (window.innerWidth <= 820) {
      tourPopover.dataset.placement = "center";
      tourPopover.style.left = "";
      tourPopover.style.top = "";
      tourPopover.style.removeProperty("--arrow-left");
      return;
    }
    tourPopover.dataset.placement = placement;
    tourPopover.style.left = `${left}px`;
    tourPopover.style.top = `${top}px`;
    const arrow = Math.max(16, Math.min(rect.left + rect.width / 2 - left - 7, width - 30));
    tourPopover.style.setProperty("--arrow-left", `${arrow}px`);
  }

  async function showTourStep(index) {
    if (tourBusy) return;
    tourBusy = true;
    tourIndex = Math.max(0, Math.min(TOUR_STEPS.length - 1, index));
    const step = TOUR_STEPS[tourIndex];
    if (step.view && state.view !== step.view) switchView(step.view, false);
    await tourWait(step.target ? 160 : 30);
    const target = step.target ? $(step.target) : null;
    if (target) {
      target.scrollIntoView({ block: "center", inline: "center", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
      await tourWait(260);
    }
    $("#tour-step-count").textContent = `${tourIndex + 1} / ${TOUR_STEPS.length}`;
    $("#tour-title").textContent = step.title;
    $("#tour-body").textContent = step.body;
    $("#tour-back").style.visibility = tourIndex === 0 ? "hidden" : "visible";
    $("#tour-next").textContent = tourIndex === TOUR_STEPS.length - 1 ? "Finish" : "Next";
    positionTour(step);
    tourBusy = false;
    tourPopover.focus({ preventScroll: true });
  }

  function startTour() {
    tourActive = true;
    tourLayer.classList.add("open");
    showTourStep(0);
  }

  function endTour(markSeen = true) {
    tourActive = false;
    tourLayer.classList.remove("open");
    if (markSeen) {
      try { localStorage.setItem("onchain-tour-seen", "1"); } catch { /* local demo */ }
    }
  }

  $("#tour-start").addEventListener("click", startTour);
  $("#tour-next").addEventListener("click", () => {
    if (tourIndex >= TOUR_STEPS.length - 1) endTour();
    else showTourStep(tourIndex + 1);
  });
  $("#tour-back").addEventListener("click", () => showTourStep(tourIndex - 1));
  $("#tour-skip").addEventListener("click", () => endTour());
  document.addEventListener("keydown", (event) => {
    if (!tourActive) return;
    if (event.key === "Escape") endTour();
    if (event.key === "ArrowRight") showTourStep(tourIndex + 1);
    if (event.key === "ArrowLeft") showTourStep(tourIndex - 1);
  });
  window.addEventListener("resize", () => {
    if (tourActive) positionTour(TOUR_STEPS[tourIndex]);
  });

  const initialView = (location.hash || "#overview").slice(1);
  state.view = document.getElementById(`view-${initialView}`) ? initialView : "overview";
  loadAll().then(() => {
    const params = new URLSearchParams(location.search);
    const force = params.get("tour") === "1";
    let seen = false;
    try { seen = Boolean(localStorage.getItem("onchain-tour-seen")); } catch { /* file:// demo */ }
    if (force || (!seen && params.get("tour") !== "0" && (!location.hash || location.hash === "#overview"))) {
      window.setTimeout(startTour, 900);
    }
  }).catch((error) => {
    state.loading = false;
    toast(`Failed to load registry: ${error.message}`, "error", 9000);
    $("#kpi-grid").innerHTML = `<div class="kpi"><div class="kpi-label">Connection error</div><div class="kpi-value">—</div><div class="kpi-sub">${esc(error.message)}</div></div>`;
  });
})();
