import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });

function response(body: Record<string, string>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Metode tidak didukung" }, 405);

  try {
    const body = await req.json() as Record<string, unknown>;
    const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const token = typeof body.token === "string" ? body.token.trim() : "";
    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    const configuredDomain = (Deno.env.get("ALLOWED_EMAIL_DOMAIN") ?? "").trim().toLowerCase().replace(/^@/, "");

    if (!fullName || !email || !password || !token) return response({ error: "Semua kolom wajib diisi" }, 400);
    if (!emailPattern.test(email)) return response({ error: "Format email tidak valid" }, 400);
    if (password.length < 8) return response({ error: "Password minimal 8 karakter" }, 400);
    if (configuredDomain && !email.endsWith(`@${configuredDomain}`)) return response({ error: "Gunakan email resmi BSI" }, 400);

    const { data: claimId, error: claimError } = await adminClient.rpc("claim_registration_token", { p_code: token });
    if (claimError || !claimId) return response({ error: "Kode pendaftaran tidak valid atau sudah tidak berlaku" }, 400);

    const { data: createdUser, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });

    if (createError || !createdUser.user) {
      await adminClient.from("invite_codes").update({ used_at: null, used_by: null }).eq("id", claimId);
      if (createError?.message.toLowerCase().includes("already been registered") || createError?.message.toLowerCase().includes("already registered")) return response({ error: "Email sudah terdaftar" }, 409);
      return response({ error: "Pendaftaran tidak dapat diproses" }, 400);
    }

    const { error: linkError } = await adminClient.from("invite_codes").update({ used_by: createdUser.user.id }).eq("id", claimId).is("used_by", null);
    if (linkError) {
      await adminClient.auth.admin.deleteUser(createdUser.user.id);
      await adminClient.from("invite_codes").update({ used_at: null, used_by: null }).eq("id", claimId);
      return response({ error: "Pendaftaran tidak dapat diproses" }, 500);
    }

    return response({ message: "Akun berhasil dibuat" }, 201);
  } catch {
    return response({ error: "Pendaftaran tidak dapat diproses" }, 500);
  }
});
