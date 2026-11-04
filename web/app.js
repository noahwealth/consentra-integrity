// Consentra · Health Passport web app
// Vanilla ES module. Supabase JS via CDN. No build step.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cfg = window.CONSENTRA ?? {};
if (!cfg.SUPABASE_URL || cfg.SUPABASE_URL.includes("YOUR-PROJECT")) {
  document.getElementById("signin").innerHTML = `<div class="glass glass--pad"><h3>Set up web/config.js</h3><p class="muted">Add your Supabase URL and anon key. See docs/HACKATHON.md.</p></div>`;
  throw new Error("config missing");
}
const sb = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const S = { user: null, patient: null, rec: null, route: "passport", scanning: false };
const $ = (sel, root = document) => root.querySelector(sel);
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v; else if (k === "html") n.innerHTML = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v); else if (v !== null && v !== undefined && v !== false) n.setAttribute(k, v === true ? "" : v);
  }
  for (const k of kids.flat(Infinity)) if (k !== null && k !== undefined && k !== false) n.append(k.nodeType ? k : document.createTextNode(String(k)));
  return n;
};
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const MON = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
const fmtDate = (d) => { if (!d) return "—"; const x = new Date(d); return `${MON[x.getMonth()]} ${x.getDate()}, ${x.getFullYear()}`; };
const fmtTs = (d) => d ? new Date(d).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) : "—";
const ago = (d) => { if (!d) return "never"; const m = Math.max(0, Math.round((Date.now() - new Date(d)) / 60000)); if (m < 1) return "just now"; if (m < 60) return `${m} min ago`; const h = Math.round(m / 60); if (h < 24) return `${h} h ago`; return `${Math.round(h / 24)} d ago`; };
const countdown = (d) => { const m = Math.max(0, Math.floor((new Date(d) - Date.now()) / 60000)); const h = Math.floor(m / 60), dd = Math.floor(h / 24); if (dd >= 1) return `${dd} d ${h % 24} h`; if (h >= 1) return `${h} h ${m % 60} min`; return `${m} min`; };
const cap = (s) => s ? s[0].toUpperCase() + s.slice(1) : "";
const kindLabel = { dose_conflict: "Dose conflict", missing_allergy: "Missing allergy", stale_medication: "Stale medication", incomplete_provider: "Incomplete provider", duplicate_record: "Duplicate record", conflicting_status: "Conflicting status", unit_mismatch: "Unit mismatch", table_trust: "Table trust", rule_breach: "Rule breach" };
const CAT = {
  medications:   { label: "Medications",   ico: "teal",   svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M10.5 20.5 3.5 13.5a4.95 4.95 0 0 1 7-7l7 7a4.95 4.95 0 0 1-7 7Z"/><path d="m8.5 8.5 7 7"/></svg>' },
  allergies:     { label: "Allergies",     ico: "orange", svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6l-8-3Z"/><path d="M12 8v5"/><circle cx="12" cy="16" r=".6" fill="currentColor"/></svg>' },
  conditions:    { label: "Conditions",    ico: "pink",   svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.6a4.6 4.6 0 0 0-8.8-2 4.6 4.6 0 0 0-8.8 2c0 5.4 8.8 10.4 8.8 10.4s8.8-5 8.8-10.4Z"/></svg>' },
  observations:  { label: "Lab Results",   ico: "purple", svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M9 3h6M10 3v6l-5.5 9A2 2 0 0 0 6.2 21h11.6a2 2 0 0 0 1.7-3L14 9V3"/></svg>' },
  immunizations: { label: "Immunizations", ico: "green",  svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="m14 4 6 6M16 8 8 16M4 20l3-3M7 13l4 4"/></svg>' },
};
let toastTimer;
function toast(msg) { const t = $("#toast"); t.textContent = msg; t.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => (t.hidden = true), 2800); }
const provIndex = () => (S.rec?.providers ?? []).map((p, i) => [p.id, i]);
const provClass = (id) => `c${((S.rec?.providers ?? []).findIndex((p) => p.id === id) % 4) + 1}`;
const provById = (id) => (S.rec?.providers ?? []).find((p) => p.id === id);
const initials = (p) => (p?.short_name ?? p?.name ?? "?").split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
const pfp = (p, cls = "pfp") => el("span", { class: `${cls} ${provClass(p?.id)}`, title: p?.name ?? "" }, initials(p));
const provTag = (p) => el("span", { class: `tag ${p?.country?.toLowerCase() ?? ""}` }, p?.short_name ?? "Unknown");
const openIssues = () => (S.rec?.discrepancies ?? []).filter((d) => d.status === "open" || d.status === "flagged");
const flaggedIds = () => new Set(openIssues().flatMap((d) => d.record_ids ?? []));
const icon = (cat, size = 34) => el("span", { class: `ico ${CAT[cat].ico}`, html: CAT[cat].svg, style: size !== 34 ? `width:${size}px;height:${size}px` : null });
const glassHover = (card) => { card.addEventListener("pointermove", (e) => { const r = card.getBoundingClientRect(); card.style.setProperty("--mx", `${e.clientX - r.left}px`); card.style.setProperty("--my", `${e.clientY - r.top}px`); }); return card; };
const glass = (...kids) => glassHover(el("div", { class: "glass glass--pad" }, ...kids));

// ---------------------------------------------------------------------------
// Auth + data
// ---------------------------------------------------------------------------
async function signIn() {
  const btn = $("#btn-signin"); btn.disabled = true; btn.textContent = "Opening…";
  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    const { error } = await sb.auth.signInAnonymously();
    if (error) { toast(error.message); btn.disabled = false; btn.textContent = "Open Noah's passport"; return; }
  }
  await bootstrap();
}
async function bootstrap() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return;
  S.user = user;
  const { data: patient, error } = await sb.rpc("claim_demo_patient");
  if (error) { toast(error.message); return; }
  S.patient = patient;
  await load();
  $("#signin").hidden = true; $("#streak").hidden = true; $("#view").hidden = false; $("#tabs").hidden = false;
  const who = $("#who"); who.innerHTML = "";
  who.append(el("button", { onclick: async () => { await sb.auth.signOut(); location.hash = ""; location.reload(); } }, "Sign out"),
             el("span", { class: "avatar", title: `${patient.given_name} ${patient.family_name}` }, `${patient.given_name[0]}${patient.family_name[0]}`));
  render();
}
async function load() {
  const { data, error } = await sb.rpc("my_record");
  if (error) { toast(error.message); return; }
  S.rec = data;
  const n = openIssues().length; const pill = $("#pill-open"); pill.hidden = n === 0; pill.textContent = n;
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------
function render() {
  const route = (location.hash.replace(/^#\//, "") || "passport").split("/")[0];
  S.route = route;
  document.querySelectorAll("#tabs a").forEach((a) => a.classList.toggle("active", a.dataset.tab === route));
  const view = $("#view"); view.innerHTML = "";
  if (!S.rec) return;
  ({ passport: Passport, scan: Scan, resolve: Resolve, share: Share }[route] ?? Passport)(view);
  view.querySelectorAll(":scope > *").forEach((n, i) => { n.classList.add("reveal"); n.dataset.delay = Math.min(i, 4); });
  window.scrollTo({ top: 0 });
}
window.addEventListener("hashchange", render);

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------
function PassCard({ badge, badgeClass, metaTop, metaBottom, wide = false } = {}) {
  const r = S.rec, p = r.patient, scan = r.last_scan, issues = openIssues();
  if (!badge) {
    if (!scan?.finished_at) { badge = "Not verified"; badgeClass = "dim"; }
    else if (issues.length) { badge = `${issues.length} in question`; badgeClass = "warn"; }
    else { badge = "Verified"; badgeClass = "ok"; }
  }
  const lastSync = r.providers.map((x) => x.last_synced).filter(Boolean).sort().pop();
  return el("div", { class: `pass ${wide ? "pass--wide" : ""}` },
    el("div", { class: "pass__top" }, el("img", { src: "assets/mark.png", alt: "" }), el("span", { class: "pass__brand" }, "Consentra"), el("span", { class: `pass__badge ${badgeClass}` }, badge)),
    el("div", { class: "pass__cap" }, "Health Passport"),
    el("div", { class: "pass__name" }, `${p.given_name} ${p.family_name}`),
    el("div", { class: "pass__foot" },
      el("div", { class: "pass__meta" }, metaTop ?? `${r.providers.length} sources connected`, el("br"), metaBottom ?? (scan?.finished_at ? `Verified ${ago(scan.finished_at)}` : `Updated ${ago(lastSync)}`)),
      el("div", { class: "cluster" }, r.providers.map((pr) => pfp(pr)))));
}
function recordRow(cat, row, { flagged = false, onclick = null } = {}) {
  const pr = provById(row.provider_id);
  let title, detail;
  switch (cat) {
    case "medications": title = row.display_name; detail = `${row.dose_value ?? ""} ${row.dose_unit ?? ""} · ${cap(row.frequency ?? "")}`.trim(); break;
    case "allergies": title = row.display_name; detail = `${cap(row.criticality ?? "")} criticality${row.reaction ? ` · ${row.reaction}` : ""}`; break;
    case "conditions": title = row.display_name; detail = `${cap(row.clinical_status)}${row.onset_on ? ` · since ${fmtDate(row.onset_on)}` : ""}`; break;
    case "observations": title = row.name; detail = `${row.value} ${row.unit}`; break;
    case "immunizations": title = row.name; detail = fmtDate(row.occurred_on); break;
  }
  const when = cat === "observations" ? row.observed_at : cat === "immunizations" ? row.occurred_on : row.recorded_at;
  return el("div", { class: `grow noicon ${flagged ? "flag" : ""} ${onclick ? "link" : ""}`, onclick },
    el("div", {}, el("div", { class: "grow__t" }, title, flagged ? el("span", { class: "tag bad" }, "In question") : null), el("div", { class: "grow__d" }, detail), el("div", { class: "grow__s" }, `${pr?.short_name ?? "Unknown"} · ${fmtDate(when)}`)),
    el("div", { class: "grow__r" }, pfp(pr), onclick ? el("span", { class: "chev" }, "›") : null));
}
function findingRow(d, onclick) {
  return el("div", { class: `grow link ${d.status === "open" || d.status === "flagged" ? "" : "off"}`, onclick },
    el("span", { class: `ico ${{ critical: "red", high: "red", medium: "orange", low: "blue" }[d.severity] ?? "grey"}`, html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 9v4M12 17h.01M10.3 4.3 2.6 18a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0Z"/></svg>' }),
    el("div", {}, el("div", { class: "grow__t" }, d.summary), el("div", { class: "grow__s" }, `${kindLabel[d.kind] ?? d.kind} · ${d.detected_by === "sodabase" ? "Sodabase" : "Consentra rule"} · ${cap(d.status)}`)),
    el("div", { class: "grow__r" }, el("span", { class: `sev ${d.status === "open" || d.status === "flagged" ? d.severity : d.status}` }, d.status === "open" || d.status === "flagged" ? d.severity : d.status), el("span", { class: "chev" }, "›")));
}

// ---------------------------------------------------------------------------
// Screen 1 · Passport (Figma 09 + 10 + 11)
// ---------------------------------------------------------------------------
function Passport(view) {
  const r = S.rec, issues = openIssues(), scan = r.last_scan, flagged = flaggedIds();
  const total = ["medications", "allergies", "conditions", "observations", "immunizations"].reduce((a, c) => a + r[c].length, 0);

  view.append(el("div", { class: "page__head" },
    el("div", {}, el("p", { class: "eyebrow" }, "Health passport"),
      el("h2", { class: "sec__title" }, "One record.", el("br"), el("span", { class: "dim" }, `${r.providers.length} hospitals' copies.`)),
      el("p", { class: "lede" }, `${total} records from ${r.providers.map((p) => p.short_name).join(", ")}. ${scan?.finished_at ? (issues.length ? `${issues.length} of them are in question.` : "All of them agree.") : "Not yet checked against each other."}`),
      el("div", { class: "cta" }, el("a", { class: "btn", href: "#/scan" }, scan?.finished_at ? "Re-run integrity scan" : "Verify my health records"), issues.length ? el("a", { class: "btn btn--ghost", href: "#/resolve" }, "Review discrepancies") : el("a", { class: "btn btn--ghost", href: "#/share" }, "Share"))),
    el("div", {}, PassCard(), el("div", { class: "pass__status" }, el("i", { class: scan?.finished_at ? "" : "off" }), scan?.finished_at ? `Verified against ${r.providers.length} sources · ${ago(scan.finished_at)}` : "Not verified yet"))));

  if (scan?.finished_at && issues.length) {
    const top = issues[0];
    view.append(el("div", { class: "request" },
      el("span", { class: `request__ico ico ${{ critical: "red", high: "red", medium: "orange", low: "blue" }[top.severity]}`, html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 9v4M12 17h.01M10.3 4.3 2.6 18a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0Z"/></svg>' }),
      el("div", {}, el("div", { class: "request__t" }, `${issues.length} discrepancies across your sources`), el("div", { class: "request__s" }, top.summary)),
      el("a", { class: "btn btn--ios", href: "#/resolve" }, "Review")));
  }

  view.append(el("div", { class: "stats" },
    el("div", { class: "stat" }, el("div", { class: "stat__n" }, total), el("div", { class: "stat__l" }, "Records")),
    el("div", { class: "stat" }, el("div", { class: "stat__n" }, r.providers.length), el("div", { class: "stat__l" }, "Providers")),
    el("div", { class: "stat" }, el("div", { class: `stat__n ${scan?.finished_at ? (issues.length ? "bad" : "ok") : "na"}` }, scan?.finished_at ? issues.length : "Not scanned yet"), el("div", { class: "stat__l" }, "In question"))));

  // Overview grid (Figma 10)
  const cats = Object.keys(CAT);
  view.append(el("div", {}, el("div", { class: "section-head" }, el("h3", {}, "Health overview"), el("span", { class: "fine" }, `From ${r.providers.length} sources`)),
    el("div", { class: "cats" }, cats.map((c) => {
      const n = r[c].length, f = r[c].filter((x) => flagged.has(x.id)).length;
      return el("a", { class: "cat", href: `#/passport/${c}`, onclick: (e) => { e.preventDefault(); $(`#sec-${c}`)?.scrollIntoView({ behavior: "smooth", block: "start" }); } },
        el("div", { class: "cat__h" }, icon(c, 26), CAT[c].label),
        el("div", { class: "cat__n" }, n, el("small", {}, c === "observations" ? "results" : c === "medications" ? "active" : "records")),
        scan?.finished_at ? el("div", { class: `cat__f ${f ? "" : "ok"}` }, f ? `${f} in question` : "Verified") : null);
    }))));

  // Sources (Figma 13)
  view.append(el("div", {}, el("div", { class: "section-head" }, el("h3", {}, "Connected sources")),
    el("div", { class: "group" }, r.providers.map((pr) => el("div", { class: "grow" },
      pfp(pr, "pfp ico"),
      el("div", {}, el("div", { class: "grow__t" }, pr.name, el("span", {}, pr.country === "GB" ? "🇬🇧" : "🇺🇸")), el("div", { class: "grow__s" }, `${pr.ehr_vendor ?? "EHR"} · ${pr.city ?? ""} · ${pr.npi ? `NPI ${pr.npi}` : pr.ods_code ? `ODS ${pr.ods_code}` : "no identifier on file"} · synced ${ago(pr.last_synced)}`)),
      el("div", { class: "grow__r" }, pr.npi || pr.ods_code ? el("span", { class: "check", style: "color:var(--ios-green)" }, "✓") : el("span", { class: "tag warn" }, "Incomplete")))))));

  // Normalization layer (migration 0003): one vocabulary, one unit, per jurisdiction
  const juris = [...new Set(r.providers.map((p) => p.jurisdiction ?? p.country))];
  view.append(el("div", {}, el("div", { class: "section-head" }, el("h3", {}, "Normalization"), el("span", { class: "fine" }, "RxNorm · LOINC · UCUM")),
    el("div", { class: "cats" }, [
      el("div", { class: "cat" }, el("div", { class: "cat__h" }, "Jurisdictions"), el("div", { class: "cat__n" }, juris.length, el("small", {}, juris.join(" · "))), el("div", { class: "cat__f ok" }, "TEFCA/IAS · NHS SPR")),
      el("div", { class: "cat" }, el("div", { class: "cat__h" }, "Drug matching"), el("div", { class: "cat__n" }, "RxNorm", el("small", {}, "+ dm+d")), el("div", { class: "cat__f ok" }, "Brand and generic resolve to one ingredient")),
      el("div", { class: "cat" }, el("div", { class: "cat__h" }, "Lab units"), el("div", { class: "cat__n" }, "UCUM", el("small", {}, "LOINC-keyed")), el("div", { class: "cat__f ok" }, "IFCC ↔ NGSP · mmol/L ↔ mg/dL")),
      el("div", { class: "cat" }, el("div", { class: "cat__h" }, "Conflicts compared"), el("div", { class: "cat__n" }, "by code", el("small", {}, "not by string")), el("div", { class: "cat__f ok" }, "Same rule at 300 or 300M rows")),
    ])));

  // Records by category (Figma 11)
  for (const c of cats) {
    const rows = r[c];
    view.append(el("div", { id: `sec-${c}` }, el("div", { class: "section-head" }, el("h3", { class: "row", style: "gap:10px" }, icon(c, 28), CAT[c].label), el("span", { class: "fine" }, `${rows.length} · from ${new Set(rows.map((x) => x.provider_id)).size} sources`)),
      el("div", { class: "group" }, rows.length ? rows.map((row) => {
        const d = flagged.has(row.id) ? openIssues().find((x) => (x.record_ids ?? []).includes(row.id)) : null;
        return recordRow(c, row, { flagged: !!d, onclick: d ? () => (location.hash = `#/resolve/${d.id}`) : null });
      }) : el("div", { class: "empty" }, "No records"))));
  }
}

// ---------------------------------------------------------------------------
// Screen 2 · Integrity scan
// ---------------------------------------------------------------------------
function Scan(view) {
  const r = S.rec, scan = r.last_scan, issues = openIssues();
  const sum = scan?.summary ?? {}, soda = sum.sodabase ?? {};

  view.append(el("div", { class: "scan" },
    el("div", {}, el("p", { class: "eyebrow" }, "Data integrity scan"),
      el("h2", { class: "sec__title" }, "Check this record", el("br"), el("span", { class: "grad" }, "against every source.")),
      el("p", { class: "lede", style: "margin:18px 0 26px" }, "Consentra runs cross-provider rules in Postgres, then asks Sodabase for its trust verdict on each underlying table and the result of three plain-language rules. Nothing leaves the database except counts and verdicts."),
      el("button", { class: "btn btn--lg", id: "btn-scan", onclick: runScan, disabled: S.scanning }, S.scanning ? "Scanning…" : scan?.finished_at ? "Run scan again" : "Verify my health records"),
      el("div", { class: "steps", id: "steps" },
        step(1, "Cross-provider rules", "Dose conflicts, missing allergies, stale medications, duplicates, status conflicts."),
        step(2, "Sodabase table trust", "Stale, empty or wrong, for every watched table."),
        step(3, "Sodabase rule checks", "Three plain-language rules over the live rows."),
        step(4, "Reconcile", "Findings upserted. Your flags and notes are kept."))),
    el("div", { class: `orb ${S.scanning ? "busy" : ""}`, id: "orb" }, el("span", { class: "ring r3" }), el("span", { class: "ring" }), el("span", { class: "ring r2" }), el("img", { src: "assets/logo-3d.png", alt: "" }))));

  if (!scan?.finished_at) return;

  view.append(el("div", { class: "stats four" },
    el("div", { class: "stat" }, el("div", { class: `stat__n ${issues.length ? "bad" : "ok"}` }, issues.length), el("div", { class: "stat__l" }, "Open findings")),
    el("div", { class: "stat" }, el("div", { class: "stat__n" }, (r.discrepancies ?? []).filter((d) => d.detected_by === "sodabase").length), el("div", { class: "stat__l" }, "From Sodabase")),
    el("div", { class: "stat" }, el("div", { class: "stat__n" }, (sum.tables_checked ?? []).length), el("div", { class: "stat__l" }, "Tables checked")),
    el("div", { class: "stat" }, el("div", { class: "stat__n" }, (r.discrepancies ?? []).filter((d) => d.status === "resolved").length), el("div", { class: "stat__l" }, "Resolved"))));

  const tables = soda.tables ?? [];
  view.append(glass(el("div", { class: "section-head" }, el("h3", {}, "Sodabase table trust"), el("span", { class: "fine" }, soda.ok ? `Scanned ${fmtTs(scan.finished_at)}` : "Not reached")),
    soda.ok
      ? el("div", { class: "verdicts" }, (sum.tables_checked ?? []).map((t) => { const v = tables.find((x) => x.table === t); const verdict = (v?.verdict ?? "unknown").toLowerCase(); return el("span", { class: `verdict ${verdict}` }, el("i"), el("code", {}, t), v ? cap(verdict) : "not watched"); }))
      : el("p", { class: "muted", style: "margin:0" }, soda.reason || "Set SODABASE_TOKEN on the edge function and re-run."),
    soda.rules?.length ? el("details", { style: "margin-top:16px" }, el("summary", {}, `${soda.rules.length} plain-language rules checked by Sodabase`),
      el("div", { class: "group", style: "margin-top:12px" }, soda.rules.map((ru) => el("div", { class: "grow noicon" }, el("div", {}, el("div", { class: "grow__d", style: "color:var(--txt)" }, ru.rule), el("div", { class: "grow__s" }, el("code", {}, ru.dataset)), ru.query ? el("details", {}, el("summary", {}, "query"), el("pre", {}, ru.query)) : null), el("span", { class: `tag ${ru.failing ? "bad" : "ok"}` }, ru.failing ? `${ru.failing} rows break it` : "Passes"))))) : null,
    soda.errors?.length ? el("details", { style: "margin-top:12px" }, el("summary", {}, "Sodabase notes"), el("pre", {}, soda.errors.join("\n"))) : null));

  view.append(el("div", {}, el("div", { class: "section-head" }, el("h3", {}, "Findings"), el("a", { class: "fine", href: "#/resolve" }, "Resolve all ›")),
    el("div", { class: "group" }, (r.discrepancies ?? []).length ? r.discrepancies.map((d) => findingRow(d, () => (location.hash = `#/resolve/${d.id}`))) : el("div", { class: "empty" }, "No discrepancies."))));
}
function step(n, t, sub) { return el("div", { class: "step", "data-step": n }, el("span", { class: "n" }, n), el("div", {}, el("h4", {}, t), el("p", {}, sub))); }
function setStep(n, state) { const s = $(`[data-step="${n}"]`); if (s) { s.classList.remove("run", "done", "fail"); if (state) s.classList.add(state); } }
async function runScan() {
  if (S.scanning) return;
  S.scanning = true; $("#btn-scan").disabled = true; $("#btn-scan").textContent = "Scanning…"; $("#orb")?.classList.add("busy");
  setStep(1, "run");
  const timers = [setTimeout(() => { setStep(1, "done"); setStep(2, "run"); }, 900), setTimeout(() => { setStep(2, "done"); setStep(3, "run"); }, 2600)];
  const { data: { session } } = await sb.auth.getSession();
  let res, body;
  try {
    res = await fetch(`${cfg.SUPABASE_URL}/functions/v1/integrity-scan`, { method: "POST", headers: { Authorization: `Bearer ${session.access_token}`, apikey: cfg.SUPABASE_ANON_KEY, "Content-Type": "application/json" }, body: "{}" });
    body = await res.json();
  } catch (e) { body = { error: e.message }; }
  timers.forEach(clearTimeout);
  S.scanning = false;
  if (!res?.ok || body.error) { setStep(1, "fail"); $("#orb")?.classList.remove("busy"); toast(`Scan failed: ${body.error ?? res?.status}`); setTimeout(render, 1200); return; }
  setStep(1, "done"); setStep(2, body.summary?.sodabase?.ok ? "done" : "fail"); setStep(3, body.summary?.sodabase?.ok ? "done" : "fail"); setStep(4, "run");
  await load();
  setStep(4, "done"); $("#orb")?.classList.remove("busy");
  toast(`${body.summary.open_total} open ${body.summary.open_total === 1 ? "finding" : "findings"}`);
  setTimeout(render, 700);
}

// ---------------------------------------------------------------------------
// Screen 3 · Resolution
// ---------------------------------------------------------------------------
function Resolve(view) {
  const r = S.rec;
  const focus = location.hash.split("/")[2];
  const list = [...(r.discrepancies ?? [])].sort((a, b) => (a.status === "open" || a.status === "flagged" ? 0 : 1) - (b.status === "open" || b.status === "flagged" ? 0 : 1));
  view.append(el("div", { class: "page__head" }, el("div", {}, el("p", { class: "eyebrow" }, "Resolution"),
    el("h2", { class: "sec__title" }, "Side by side,", el("br"), el("span", { class: "dim" }, "with the source.")),
    el("p", { class: "lede" }, "Every conflicting record with the provider that holds it and when they last touched it. Flag anything a provider needs to see; it travels with your shared passport as an open question, never silently merged.")),
    el("div", { class: "stats" },
      el("div", { class: "stat" }, el("div", { class: "stat__n bad" }, list.filter((d) => d.status === "open").length), el("div", { class: "stat__l" }, "Open")),
      el("div", { class: "stat" }, el("div", { class: "stat__n" }, list.filter((d) => d.status === "flagged").length), el("div", { class: "stat__l" }, "Flagged for provider")),
      el("div", { class: "stat" }, el("div", { class: "stat__n ok" }, list.filter((d) => d.status === "resolved" || d.status === "dismissed").length), el("div", { class: "stat__l" }, "Closed")))));
  if (!list.length) { view.append(el("div", { class: "glass empty" }, "Nothing to resolve. Run a scan first.")); return; }
  for (const d of list) { const c = ResolveCard(d); if (d.id === focus) { c.classList.add("glass--hot"); setTimeout(() => c.scrollIntoView({ behavior: "smooth", block: "center" }), 350); } view.append(c); }
}
function ResolveCard(d) {
  const det = d.detail ?? {}, live = d.status === "open" || d.status === "flagged";
  const card = glassHover(el("div", { class: `glass glass--pad finding ${live ? "" : "closed"}` }));
  card.append(el("div", { class: "finding__head" }, el("span", { class: `sev ${live ? d.severity : d.status}`, style: "margin-top:6px" }, live ? d.severity : d.status), el("h3", {}, d.summary),
    el("div", { class: "finding__meta" }, el("span", { class: `tag ${d.detected_by === "sodabase" ? "soda" : "violet"}` }, d.detected_by === "sodabase" ? "Sodabase" : "Consentra rule"), el("span", { class: "tag" }, kindLabel[d.kind] ?? d.kind), d.status === "flagged" ? el("span", { class: "tag info" }, "Flagged for provider") : null)));

  const src = (o, { val, sub, cls = "" } = {}) => { const pr = provById(o.provider_id) ?? { short_name: o.provider }; return el("div", { class: `src ${cls}` }, el("div", { class: "src__prov" }, pfp(pr), pr.short_name), el("div", { class: "src__val" }, val ?? "—"), sub ? el("div", { class: "src__sub" }, sub) : null, el("div", { class: "src__ts" }, o.recorded_at ? `Updated ${fmtDate(o.recorded_at)}` : "")); };
  let compare = null;
  if (d.kind === "dose_conflict" && det.sources) { const latest = [...det.sources].sort((a, b) => new Date(b.recorded_at) - new Date(a.recorded_at))[0]; compare = det.sources.map((s) => src(s, { val: `${s.canonical_dose ?? s.dose_value} ${s.canonical_unit ?? s.dose_unit}`, sub: `${s.display_name}${s.canonical_dose != null && (s.canonical_dose !== s.dose_value || s.canonical_unit !== s.dose_unit) ? ` · as recorded: ${s.dose_value} ${s.dose_unit}` : ""}${det.rxcui ? ` · RxNorm ${det.rxcui}` : ""}`, cls: s === latest ? "latest" : "" })); }
  else if (d.kind === "missing_allergy" && det.known_at) compare = [...det.known_at.map((s) => src(s, { val: cap(det.substance), sub: `${cap(det.criticality)} criticality · ${s.reaction ?? ""}` })), el("div", { class: "src missing" }, el("div", { class: "src__prov" }, pfp(provById(det.missing_at_id) ?? { short_name: det.missing_at }), det.missing_at), el("div", { class: "src__val" }, "Not on file"), el("div", { class: "src__sub" }, "No allergy record for this substance"), el("div", { class: "src__ts" }, "Could be missed at intake"))];
  else if (d.kind === "stale_medication") compare = [src(det, { val: det.display_name, sub: `Still marked active · ${det.months_stale} months without review` })];
  else if (d.kind === "conflicting_status" && det.sources) compare = det.sources.map((s) => src(s, { val: cap(s.status), sub: cap(det.condition) }));
  else if (d.kind === "duplicate_record") compare = [src(det, { val: `${det.count}× ${cap(det.drug)}`, sub: "Same drug entered twice, both active" })];
  else if (d.kind === "incomplete_provider") compare = [src(det, { val: "No NPI · No ODS", sub: "Records can't be cross-referenced to a registry" })];
  else if (d.kind === "table_trust" || d.kind === "rule_breach") compare = [el("div", { class: "src", style: "grid-column:1/-1" }, el("div", { class: "src__prov" }, el("span", { class: "tag soda" }, "Sodabase"), el("code", {}, d.record_table)), det.rule ? el("div", { class: "src__sub", style: "margin-top:10px" }, det.rule) : null, det.failing_rows != null ? el("div", { class: "src__val" }, `${det.failing_rows} rows`) : det.verdict ? el("div", { class: "src__val" }, cap(det.verdict)) : null, det.query ? el("details", { style: "margin-top:8px;color:var(--ios-2)" }, el("summary", { style: "color:var(--ios-2)" }, "query Sodabase would run"), el("pre", { style: "color:#333;background:rgba(0,0,0,.05);border:0" }, det.query)) : null)];
  if (compare) card.append(el("div", { class: "compare" }, compare));

  if (d.flagged_note) card.append(el("div", { class: "note" }, el("b", {}, "Your note · "), d.flagged_note));
  card.append(EvidenceRow(d, live));
  const note = el("textarea", { placeholder: "Note for the provider (optional) — e.g. Boston raised my dose in October; London was never told." });
  const act = (status) => async () => { const { error } = await sb.rpc("set_discrepancy_status", { d: d.id, s: status, note: note.value || null }); if (error) return toast(error.message); toast(status === "flagged" ? "Flagged for provider review" : `Marked ${status}`); await load(); render(); };
  if (live) card.append(el("div", { class: "actions" }, note, el("div", { class: "row" },
    el("button", { class: "btn", onclick: act("flagged") }, d.status === "flagged" ? "Update note" : "Flag for provider review"),
    el("button", { class: "btn btn--ghost", onclick: act("resolved") }, "Mark resolved"),
    el("button", { class: "btn btn--ghost", onclick: act("dismissed") }, "Dismiss"))));
  else card.append(el("div", { class: "row" }, el("button", { class: "btn btn--ghost btn--sm", onclick: async () => { await sb.rpc("set_discrepancy_status", { d: d.id, s: "open" }); await load(); render(); } }, "Reopen")));
  return card;
}

// Evidence attachments (Supabase Storage, private bucket, RLS by patient folder)
function EvidenceRow(d, live) {
  const items = (S.rec.evidence ?? []).filter((e) => e.discrepancy_id === d.id);
  const box = el("div", { class: "evidence" });
  const list = el("div", { class: "evidence__list" }, items.map((e) => el("div", { class: "evidence__item" },
    el("span", { class: "ico grey", html: e.mime_type === "application/pdf" ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5"/></svg>' : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m21 16-5-5-8 8"/></svg>' }),
    el("div", { style: "flex:1;min-width:0" }, el("div", { class: "grow__t" }, e.caption || e.file_name), el("div", { class: "grow__s" }, `${e.file_name} · ${Math.round(e.size_bytes / 1024)} KB · ${fmtDate(e.created_at)}`)),
    el("button", { class: "btn btn--ghost btn--sm", onclick: async () => { const { data, error } = await sb.storage.from("evidence").createSignedUrl(e.object_path, 120); if (error) return toast(error.message); window.open(data.signedUrl, "_blank", "noopener"); } }, "View"),
    live ? el("button", { class: "btn btn--ghost btn--sm", onclick: async () => { await sb.storage.from("evidence").remove([e.object_path]); await sb.from("evidence").delete().eq("id", e.id); toast("Removed"); await load(); render(); } }, "Remove") : null)));
  box.append(el("div", { class: "evidence__head" }, el("span", { class: "fine", style: "font-family:var(--f-display);letter-spacing:.14em;text-transform:uppercase;font-weight:600" }, items.length ? `Evidence · ${items.length}` : "Evidence"),
    live ? el("label", { class: "btn btn--ghost btn--sm", style: "cursor:pointer" }, "Attach photo or PDF",
      el("input", { type: "file", accept: "image/*,application/pdf", hidden: true, onchange: async (ev) => {
        const f = ev.target.files?.[0]; if (!f) return;
        if (f.size > 10 * 1024 * 1024) return toast("Max 10 MB");
        const caption = prompt("What does this show? (e.g. Boston prescription label, 20 mg)", "") ?? "";
        const safe = f.name.replace(/[^A-Za-z0-9._-]/g, "_");
        const path = `${S.patient.id}/${d.id}/${Date.now()}-${safe}`;
        toast("Uploading…");
        const { error } = await sb.storage.from("evidence").upload(path, f, { contentType: f.type, upsert: false });
        if (error) return toast(error.message);
        const { error: e2 } = await sb.from("evidence").insert({ patient_id: S.patient.id, discrepancy_id: d.id, object_path: path, file_name: f.name, mime_type: f.type || "application/octet-stream", size_bytes: f.size, caption: caption || null });
        if (e2) return toast(e2.message);
        toast("Evidence attached"); await load(); render();
      } })) : null));
  if (items.length) box.append(list);
  return box;
}

// ---------------------------------------------------------------------------
// Screen 4 · Verified sharing (Figma 18 / 16 / 20)
// ---------------------------------------------------------------------------
function Share(view) {
  const r = S.rec, issues = openIssues(), scan = r.last_scan;
  view.append(el("div", { class: "page__head" }, el("div", {}, el("p", { class: "eyebrow" }, "Verified sharing"),
    el("h2", { class: "sec__title" }, "A passport a", el("br"), el("span", { class: "grad" }, "clinician can trust.")),
    el("p", { class: "lede" }, "Choose what to share and for how long. The clinician gets a read-only page: verified records plainly, and anything still in question clearly labeled.")),
    el("div", {}, PassCard({ metaBottom: `${issues.length} open question${issues.length === 1 ? "" : "s"} · ${(r.discrepancies ?? []).filter((d) => d.status === "resolved").length} resolved` }))));

  const cats = Object.keys(CAT);
  const state = { label: "", cats: new Set(["medications", "allergies"]), hours: 24, unresolved: true };
  const label = el("input", { type: "text", placeholder: "Dr. Rivera, Mass General", oninput: (e) => (state.label = e.target.value) });
  const catList = el("div", { class: "group" }, cats.map((c) => {
    const row = el("div", { class: `grow link ${state.cats.has(c) ? "" : "off"}` });
    row.append(icon(c), el("div", {}, el("div", { class: "grow__t" }, CAT[c].label), el("div", { class: "grow__s" }, `${r[c].length} ${c === "observations" ? "results" : "records"}${issues.some((d) => d.record_table === c) ? ` · ${issues.filter((d) => d.record_table === c).length} in question` : ""}`)),
      el("span", { class: "grow__r" }, state.cats.has(c) ? el("span", { class: "check" }, "✓") : el("span", { class: "notshared" }, "Not shared")));
    row.onclick = () => { state.cats.has(c) ? state.cats.delete(c) : state.cats.add(c); row.classList.toggle("off", !state.cats.has(c)); row.lastChild.innerHTML = ""; row.lastChild.append(state.cats.has(c) ? el("span", { class: "check" }, "✓") : el("span", { class: "notshared" }, "Not shared")); };
    return row;
  }));
  const seg = el("div", { class: "seg" }, [[1, "1 hour"], [24, "24 hours"], [168, "7 days"], [720, "30 days"]].map(([h, t]) => el("button", { class: h === 24 ? "on" : "", onclick: (e) => { state.hours = h; seg.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === e.currentTarget)); } }, t)));
  const sw = el("button", { class: "switch on", role: "switch", "aria-checked": "true", onclick: () => { state.unresolved = !state.unresolved; sw.classList.toggle("on", state.unresolved); sw.setAttribute("aria-checked", String(state.unresolved)); } });
  const form = glass(el("div", { class: "section-head" }, el("h3", {}, "Share with a provider"), el("span", { class: "fine" }, "QR code or secure link")),
    el("div", { class: "actions", style: "gap:18px" },
      el("div", { class: "field" }, el("span", {}, "Who is this for"), label),
      el("div", { class: "field" }, el("span", {}, "Can access"), catList),
      el("div", { class: "field" }, el("span", {}, "Access ends after"), seg),
      el("div", { class: "group" }, el("div", { class: "grow" }, el("span", { class: "ico gold", html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 9v4M12 17h.01M10.3 4.3 2.6 18a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0Z"/></svg>' }), el("div", {}, el("div", { class: "grow__t" }, "Show open questions"), el("div", { class: "grow__s" }, `${issues.length} unresolved ${issues.length === 1 ? "discrepancy" : "discrepancies"} shown to the clinician, with your notes`)), sw)),
      el("div", { class: "row" }, el("button", { class: "btn", onclick: async () => {
        if (!state.cats.size) return toast("Pick at least one category");
        const { data, error } = await sb.from("shares").insert({ patient_id: S.patient.id, label: state.label || "Clinician", categories: [...state.cats], include_unresolved: state.unresolved, expires_at: new Date(Date.now() + state.hours * 3600e3).toISOString() }).select().single();
        if (error) return toast(error.message);
        toast("Share created"); await load(); location.hash = `#/share/${data.token}`; render();
      } }, "Create share"), el("span", { class: "fine" }, "Nothing is shared by default. Every access appears in Activity."))));

  const sharesBox = el("div", { id: "shares", class: "actions", style: "gap:14px" }, el("div", { class: "empty" }, "Loading…"));
  view.append(el("div", { class: "two" }, form, el("div", {}, el("div", { class: "section-head" }, el("h3", {}, "Who has access")), sharesBox)));
  loadShares();
}
async function loadShares() {
  const box = $("#shares"); if (!box) return;
  const { data, error } = await sb.from("shares").select("*").order("created_at", { ascending: false });
  if (error) { box.textContent = error.message; return; }
  box.innerHTML = "";
  if (!data.length) { box.append(el("div", { class: "glass empty" }, "No one has access yet.")); return; }
  const focus = location.hash.split("/")[2];
  data.forEach((s, i) => {
    const live = !s.revoked_at && new Date(s.expires_at) > new Date();
    const url = `${location.origin}${location.pathname.replace(/[^/]*$/, "")}s/${s.token}`;
    if (live && (focus === s.token || (!focus && i === 0))) {
      let qrBox = null;
      if (typeof qrcode === "function") { const qr = qrcode(0, "M"); qr.addData(url); qr.make(); qrBox = el("div", { class: "qr", html: qr.createSvgTag({ cellSize: 4, margin: 0, scalable: true }) }); }
      box.append(el("div", { class: "pass pass--wide pass--qr" }, qrBox,
        el("div", {}, el("div", { class: "pass__top" }, el("img", { src: "assets/mark.png", alt: "" }), el("span", { class: "pass__brand" }, "Consentra"), el("span", { class: "pass__badge" }, "Active")),
          el("div", { class: "pass__cap" }, "Shared with"), el("div", { class: "pass__name", style: "font-size:22px" }, s.label),
          el("div", { class: "pass__sub" }, s.categories.map((c) => CAT[c]?.label ?? c).join(" · ")),
          el("div", { class: "countdown", style: "margin-top:10px" }, "Expires in ", el("b", {}, countdown(s.expires_at)), ` · opened ${s.view_count}×`),
          el("div", { class: "row", style: "margin-top:14px;gap:8px" }, el("a", { class: "btn btn--ios", href: url, target: "_blank", rel: "noopener" }, "Open clinician view"), el("button", { class: "btn btn--ghost btn--sm", style: "color:#333;border-color:rgba(0,0,0,.15);background:rgba(0,0,0,.04)", onclick: () => { navigator.clipboard.writeText(url); toast("Link copied"); } }, "Copy link")))));
    }
    box.append(el("div", { class: "group" }, el("div", { class: "grow" }, el("span", { class: `ico ${live ? "blue" : "grey"}`, html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M14 10a4 4 0 1 1 4 4h-1v1h-1v1h-1v1h-1v1H8v-3l6-6Z"/><circle cx="17" cy="7" r="1" fill="currentColor"/></svg>' }),
      el("div", {}, el("div", { class: "grow__t" }, s.label), el("div", { class: "grow__s" }, `${s.categories.map((c) => CAT[c]?.label ?? c).join(", ")} · ${live ? `ends in ${countdown(s.expires_at)}` : s.revoked_at ? `revoked ${ago(s.revoked_at)}` : "expired"} · opened ${s.view_count}×`)),
      el("div", { class: "grow__r" }, live ? el("button", { class: "btn btn--danger btn--sm", onclick: async () => { await sb.from("shares").update({ revoked_at: new Date().toISOString() }).eq("id", s.id); toast("Access revoked"); loadShares(); } }, "Revoke") : el("span", { class: "tag" }, "Ended")))));
  });
}

// ---------------------------------------------------------------------------
$("#btn-signin").onclick = signIn;
sb.auth.getSession().then(({ data: { session } }) => { if (session) bootstrap(); });
