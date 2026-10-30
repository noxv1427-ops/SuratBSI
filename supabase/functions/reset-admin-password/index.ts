import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function response(body: Record<string, string>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function temporaryPassword(): string {
  const values = new Uint32Array(10);
  crypto.getRandomValues(values);
  return Array.from(values, (value) => alphabet[value % alphabet.length]).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Metode tidak didukung" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return response({ error: "Akses ditolak" }, 401);
    const token = authorization.slice(7);
    const { data: actorData, error: actorError } = await adminClient.auth.getUser(token);
    if (actorError || !actorData.user) return response({ error: "Akses ditolak" }, 401);

    const { data: actor } = await adminClient.from("profiles").select("role").eq("id", actorData.user.id).maybeSingle();
    const body = await req.json() as Record<string, unknown>;
    const targetId = typeof body.user_id === "string" ? body.user_id : "";
    if (actor?.role !== "super_admin" || !targetId) return response({ error: "Akses ditolak" }, 403);

    const { data: target } = await adminClient.from("profiles").select("role").eq("id", targetId).maybeSingle();
    if (!target || target.role !== "admin") return response({ error: "Akun tidak dapat direset" }, 400);

    const password = temporaryPassword();
    const { error: updateError } = await adminClient.auth.admin.updateUserById(targetId, { password });
    if (updateError) return response({ error: "Password tidak dapat direset" }, 500);
    const { error: profileError } = await adminClient.from("profiles").update({ must_change_password: true }).eq("id", targetId);
    if (profileError) return response({ error: "Password tidak dapat direset" }, 500);

    return response({ temporary_password: password });
  } catch {
    return response({ error: "Password tidak dapat direset" }, 500);
  }
});
