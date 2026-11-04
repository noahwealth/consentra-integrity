// Consentra · integrity-scan edge function
//
// POST /functions/v1/integrity-scan   (Authorization: Bearer <patient JWT>)
//
// 1. Identifies the calling patient (RLS: a user owns exactly one patient).
// 2. Runs Consentra's cross-provider rules in Postgres (detect_discrepancies).
// 3. Asks Sodabase, over its MCP endpoint, for the data-trust verdict of every
//    watched table and for the result of a few plain-language rules. Sodabase
//    never returns rows; it returns verdicts, counts and finding ids.
// 4. Upserts everything into `discrepancies` and closes the scan.
//
// Secrets (supabase secrets set ...):
//   SODABASE_TOKEN   Sodabase MCP access token (Settings → MCP → Create token)
//   SODABASE_MCP_URL optional, default https://sodabase.io/mcp
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY are injected by the platform.

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// ---------------------------------------------------------------------------
// Minimal MCP client (Streamable HTTP, bearer auth). Enough for tools/call.
// ---------------------------------------------------------------------------
class McpClient {
  #url: string; #token: string; #session: string | null = null; #id = 0;
  constructor(url: string, token: string) { this.#url = url; this.#token = token; }

  async #rpc(method: string, params: Record<string, unknown> = {}, notify = false, timeoutMs = 25_000) {
    const body: Record<string, unknown> = { jsonrpc: "2.0", method, params };
    if (!notify) body.id = ++this.#id;
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "Accept": "application/json, text/event-stream",
      "Authorization": `Bearer ${this.#token}`,
    };
    if (this.#session) headers["Mcp-Session-Id"] = this.#session;
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const res = await fetch(this.#url, { method: "POST", headers, body: JSON.stringify(body), signal: ctl.signal });
      const sid = res.headers.get("mcp-session-id");
      if (sid) this.#session = sid;
      if (notify) return null;
      if (!res.ok) throw new Error(`MCP ${method} → HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
      const ct = res.headers.get("content-type") ?? "";
      let msg: any;
      if (ct.includes("text/event-stream")) {
        // Take the last JSON-RPC message with our id from the stream.
        const text = await res.text();
        for (const line of text.split("\n")) {
          if (!line.startsWith("data:")) continue;
          try { const m = JSON.parse(line.slice(5).trim()); if (m.id === body.id) msg = m; } catch { /* ignore */ }
        }
      } else {
        msg = await res.json();
      }
      if (!msg) throw new Error(`MCP ${method}: no response message`);
      if (msg.error) throw new Error(`MCP ${method}: ${msg.error.message ?? JSON.stringify(msg.error)}`);
      return msg.result;
    } finally { clearTimeout(timer); }
  }

  async init() {
    await this.#rpc("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "consentra-integrity-scan", version: "0.1.0" },
    });
    await this.#rpc("notifications/initialized", {}, true);
  }

  /** Calls a tool and returns its text content parsed as JSON when possible. */
  async call(name: string, args: Record<string, unknown> = {}, timeoutMs?: number) {
    const result = await this.#rpc("tools/call", { name, arguments: args }, false, timeoutMs);
    const texts = (result?.content ?? []).filter((c: any) => c.type === "text").map((c: any) => c.text);
    const raw = texts.join("\n");
    if (result?.structuredContent) return result.structuredContent;
    try { return JSON.parse(raw); } catch { return { text: raw }; }
  }
}

// Plain-language rules we ask Sodabase to check against the live tables.
// These mirror Consentra's own SQL rules so the two detectors can be compared.
const SODABASE_RULES: { dataset: string; rule: string; kind: string; severity: string; summary: (n: number) => string }[] = [
  { dataset: "medications", kind: "rule_breach", severity: "high",
    rule: "Rows with the same patient_id and name where status = 'active' must have the same dose_value and dose_unit across different provider_id values.",
    summary: (n) => `Sodabase found ${n} active medication rows whose dose disagrees across providers` },
  { dataset: "medications", kind: "rule_breach", severity: "medium",
    rule: "Rows where status = 'active' and ended_on is null must have recorded_at within the last 24 months.",
    summary: (n) => `Sodabase found ${n} active medications not reviewed in over 24 months` },
  { dataset: "providers", kind: "rule_breach", severity: "low",
    rule: "Every row must have at least one of npi or ods_code not null.",
    summary: (n) => `Sodabase found ${n} providers with no identifier` },
];

const WATCHED = ["medications", "allergies", "conditions", "observations", "immunizations", "providers", "patients"];

function verdictSeverity(v: string): string {
  switch ((v ?? "").toLowerCase()) {
    case "untrusted": return "high";
    case "caveated": return "medium";
    case "unknown": case "scanning": return "low";
    default: return "low";
  }
}

async function runSodabase(scanId: string) {
  const token = Deno.env.get("SODABASE_TOKEN");
  const url = Deno.env.get("SODABASE_MCP_URL") ?? "https://sodabase.io/mcp";
  if (!token) return { ok: false, reason: "SODABASE_TOKEN not set", findings: [] as any[], tables: [] as any[], rules: [] as any[] };

  const mcp = new McpClient(url, token);
  const out = { ok: true, reason: "", findings: [] as any[], tables: [] as any[], rules: [] as any[], errors: [] as string[] };
  try {
    await mcp.init();
  } catch (e) {
    return { ...out, ok: false, reason: `init failed: ${(e as Error).message}` };
  }

  // Kick a fresh scan (fire and forget; the result arrives on a later call).
  mcp.call("data_trust_scan", {}, 8_000).catch((e) => out.errors.push(`data_trust_scan: ${e.message}`));

  // Table verdicts.
  try {
    const health = await mcp.call("data_trust_health", {}, 20_000);
    const list: any[] = Array.isArray(health) ? health : (health?.tables ?? health?.datasets ?? health?.results ?? []);
    for (const t of list) {
      const name: string = t.table ?? t.dataset ?? t.name ?? "";
      const short = name.split(".").pop() ?? name;
      const verdict: string = t.verdict ?? t.status ?? "unknown";
      const problems: any[] = t.problems ?? t.findings ?? [];
      out.tables.push({ table: short, verdict, problems });
      if (!WATCHED.includes(short)) continue;
      if (verdict.toLowerCase() === "trusted" && problems.length === 0) continue;
      out.findings.push({
        kind: "table_trust", severity: verdictSeverity(verdict), record_table: short,
        fingerprint: `sodabase:table:${short}`,
        summary: problems.length
          ? `Sodabase rates the ${short} table "${verdict}": ${problems.map((p) => `${p.name ?? p.kind ?? p.problem ?? "issue"} (${p.count ?? "?"})`).join(", ")}`
          : `Sodabase rates the ${short} table "${verdict}"`,
        detail: { verdict, problems, source: "data_trust_health" },
        sodabase_finding: problems[0]?.finding_id ?? problems[0]?.id ?? null,
      });
    }
    if (!list.length) out.errors.push(`data_trust_health returned no tables (${JSON.stringify(health).slice(0, 200)})`);
  } catch (e) { out.errors.push(`data_trust_health: ${(e as Error).message}`); }

  // Plain-language rules, in parallel, each with its own timeout.
  const ruleResults = await Promise.allSettled(
    SODABASE_RULES.map((r) => mcp.call("check_rule", { dataset: r.dataset, rule: r.rule }, 25_000).then((res) => ({ r, res })))
  );
  for (const rr of ruleResults) {
    if (rr.status === "rejected") { out.errors.push(`check_rule: ${rr.reason?.message ?? rr.reason}`); continue; }
    const { r, res } = rr.value;
    const n: number = Number(res?.failing_rows ?? res?.rows_breaking ?? res?.violations ?? res?.count ?? res?.failures ?? 0) || 0;
    out.rules.push({ dataset: r.dataset, rule: r.rule, failing: n, query: res?.query ?? res?.sql ?? null, raw: res });
    if (n > 0) {
      out.findings.push({
        kind: r.kind, severity: r.severity, record_table: r.dataset,
        fingerprint: `sodabase:rule:${r.dataset}:${r.rule.slice(0, 48)}`,
        summary: r.summary(n),
        detail: { rule: r.rule, failing_rows: n, query: res?.query ?? res?.sql ?? null, source: "check_rule", scan_id: scanId },
        sodabase_finding: res?.finding_id ?? res?.id ?? null,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "missing bearer token" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: { user }, error: uerr } = await userClient.auth.getUser();
  if (uerr || !user) return json({ error: "invalid session" }, 401);

  const { data: patient, error: perr } = await userClient.from("patients").select("id, given_name, family_name").eq("auth_user_id", user.id).maybeSingle();
  if (perr || !patient) return json({ error: "no patient for this user; call claim_demo_patient first" }, 404);

  const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: scan, error: serr } = await svc.from("integrity_scans").insert({ patient_id: patient.id, created_by: user.id }).select("id, started_at").single();
  if (serr) return json({ error: serr.message }, 500);

  // 1. Consentra rules in Postgres.
  const { data: rules, error: derr } = await svc.rpc("detect_discrepancies", { p: patient.id });
  if (derr) return json({ error: derr.message }, 500);
  const { data: n1, error: e1 } = await svc.rpc("upsert_discrepancies", { p: patient.id, scan: scan.id, detector: "consentra", findings: rules ?? [] });
  if (e1) return json({ error: e1.message }, 500);

  // 2. Sodabase, over MCP.
  const soda = await runSodabase(scan.id);
  let n2 = 0;
  if (soda.ok) {
    const { data, error } = await svc.rpc("upsert_discrepancies", { p: patient.id, scan: scan.id, detector: "sodabase", findings: soda.findings });
    if (error) soda.errors?.push(`upsert: ${error.message}`); else n2 = data ?? 0;
  }

  // 3. Close the scan.
  const { data: all } = await svc.from("discrepancies").select("kind, severity, status, detected_by").eq("patient_id", patient.id);
  const counts: Record<string, number> = {};
  for (const d of all ?? []) counts[d.kind] = (counts[d.kind] ?? 0) + (d.status === "open" || d.status === "flagged" ? 1 : 0);
  const summary = {
    consentra: { findings: n1 ?? 0 },
    sodabase: { ok: soda.ok, reason: soda.reason, findings: n2, tables: soda.tables, rules: soda.rules, errors: soda.errors ?? [] },
    open_by_kind: counts,
    open_total: Object.values(counts).reduce((a, b) => a + b, 0),
    tables_checked: WATCHED,
  };
  await svc.from("integrity_scans").update({ finished_at: new Date().toISOString(), sodabase_ok: soda.ok, summary }).eq("id", scan.id);

  return json({ scan_id: scan.id, patient: patient.id, summary });
});
