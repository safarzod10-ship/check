// PAYVAND — отправка push-уведомлений через Firebase Cloud Messaging (HTTP v1).
//
// Вызывается Database Webhook-ом Supabase при INSERT в public.messages.
// Секреты (задаются командой `supabase secrets set`, в APK их нет):
//   FCM_SERVICE_ACCOUNT  — JSON сервисного аккаунта Firebase (одной строкой)
//   PUSH_WEBHOOK_SECRET  — произвольная строка; та же строка в заголовке x-payvand-secret у webhook
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY подставляются платформой автоматически.
//
// ВНИМАНИЕ: функция написана по документации FCM и НЕ была проверена на реальном проекте Firebase.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

let cached: { token: string; exp: number } | null = null;

const b64url = (data: ArrayBuffer | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = (sa.private_key as string).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${header}.${claim}.${b64url(sig)}`,
  });
  const json = await res.json();
  cached = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cached.token;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-payvand-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) return new Response("forbidden", { status: 403 });
  const payload = await req.json();
  const id = payload?.record?.id;
  if (payload?.type !== "INSERT" || !id) return new Response("ignored");

  const { data: targets, error } = await supabase.rpc("push_targets", { m: id });
  if (error) return new Response(error.message, { status: 500 });
  if (!targets?.length) return new Response("no targets");

  const token = await accessToken();
  const results = await Promise.all(targets.map(async (t: Record<string, string>) => {
    // data-only сообщение: текст уведомления формирует само приложение на языке пользователя
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message: {
        token: t.token, android: { priority: "HIGH" },
        data: { conversation_id: t.conversation_id, title: t.title ?? "", sender: t.sender ?? "", body: (t.body ?? "").slice(0, 300), kind: t.kind, direct: String(t.direct) },
      } }),
    });
    // токен больше не действителен (приложение удалено) — убираем его
    if (res.status === 404 || res.status === 410) await supabase.from("device_tokens").delete().eq("token", t.token);
    return res.status;
  }));
  return new Response(JSON.stringify({ sent: results.length, statuses: results }), { headers: { "Content-Type": "application/json" } });
});
