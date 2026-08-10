import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async () => {
  // 16 random bytes → base64url (Play Integrity nonce must be base64url, 16–500 bytes)
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const nonce = btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  return new Response(JSON.stringify({ nonce }), {
    headers: { "Content-Type": "application/json" },
  });
});