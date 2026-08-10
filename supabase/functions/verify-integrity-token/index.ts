import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const PACKAGE_NAME = "com.alignpod.app";

// Service account JSON is stored as a Supabase secret: GOOGLE_SERVICE_ACCOUNT_JSON
async function getAccessToken(): Promise<string> {
  const serviceAccount = JSON.parse(
    Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? "{}"
  );

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/playintegrity",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encode = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

  const signingInput = `${encode(header)}.${encode(payload)}`;

  // Import private key and sign
  const pemKey = serviceAccount.private_key as string;
  const pemBody = pemKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );
  const jwt = `${signingInput}.${btoa(
    String.fromCharCode(...new Uint8Array(signature))
  )
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")}`;

  // Exchange JWT for access token
  const tokenResp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenData = await tokenResp.json();
  return tokenData.access_token as string;
}

serve(async (req) => {
  const { token } = await req.json();
  if (!token) {
    return new Response(JSON.stringify({ passed: false, error: "no token" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const accessToken = await getAccessToken();

    const resp = await fetch(
      `https://playintegrity.googleapis.com/v1/${PACKAGE_NAME}:decodeIntegrityToken`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ integrity_token: token }),
      }
    );

    const data = await resp.json();
    const verdict = data?.tokenPayloadExternal?.deviceIntegrity?.deviceRecognitionVerdict ?? [];
    const appVerdict = data?.tokenPayloadExternal?.appIntegrity?.appRecognitionVerdict ?? "";

    // Pass if device is recognized AND app is from Play Store
    const passed =
      (verdict.includes("MEETS_DEVICE_INTEGRITY") ||
        verdict.includes("MEETS_BASIC_INTEGRITY")) &&
      appVerdict === "PLAY_RECOGNIZED";

    return new Response(JSON.stringify({ passed, verdict, appVerdict }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("verify-integrity-token error:", e);
    // Fail open — don't block users if verification service errors
    return new Response(JSON.stringify({ passed: true, error: String(e) }), {
      headers: { "Content-Type": "application/json" },
    });
  }
});