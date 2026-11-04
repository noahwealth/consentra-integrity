// Consentra · share-evidence edge function
//
// GET /functions/v1/share-evidence?token=<share token>&id=<evidence id>
//   → 302 to a 10-minute signed URL for the file, or 403/404 JSON.
//
// The clinician never sees a bucket path. The function checks, in SQL, that the
// share is active, includes open questions, and that the evidence belongs to a
// discrepancy that is still open or flagged — then mints the signed URL with the
// service role. Revoking the share closes the door immediately.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "GET, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";
  const id = url.searchParams.get("id") ?? "";
  if (!/^[A-Za-z0-9_-]{16,}$/.test(token) || !/^[0-9a-f-]{36}$/.test(id)) return json({ error: "bad request" }, 400);

  const svc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: path, error } = await svc.rpc("evidence_for_share", { t: token, e: id });
  if (error) return json({ error: error.message }, 500);
  if (!path) return json({ error: "not available through this share" }, 403);

  const { data: signed, error: serr } = await svc.storage.from("evidence").createSignedUrl(path, 600);
  if (serr || !signed?.signedUrl) return json({ error: serr?.message ?? "could not sign" }, 500);
  if (url.searchParams.get("json") === "1") return json({ url: signed.signedUrl, expires_in: 600 });
  return new Response(null, { status: 302, headers: { ...CORS, Location: signed.signedUrl, "Cache-Control": "no-store" } });
});
