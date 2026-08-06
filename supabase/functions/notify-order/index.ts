// Supabase Edge Function: notify-order
// Trigger: Database Webhook on order_requests INSERT
// Sends confirmation email to customer via Resend API.
//
// Setup in Supabase Dashboard:
//   1. Deploy this function: supabase functions deploy notify-order
//   2. Add secret: supabase secrets set RESEND_API_KEY=re_xxxx
//   3. Add secret: supabase secrets set NOTIFY_EMAIL=your@email.com  (gets CC on every order)
//   4. In Supabase Dashboard → Database → Webhooks → Create Webhook:
//      Table: order_requests | Event: INSERT | URL: https://<project>.supabase.co/functions/v1/notify-order

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const NOTIFY_EMAIL = Deno.env.get("NOTIFY_EMAIL") ?? "";

serve(async (req) => {
  try {
    const body = await req.json();
    // Supabase webhook wraps the row under `record`
    const row = body.record ?? body;

    const { full_name, email, phone, quantity, delivery_address, notes } = row;

    // 1. Confirmation email to customer
    await sendEmail({
      to: email,
      subject: "We got your AlignPod order request!",
      html: customerEmailHtml({ full_name, quantity }),
    });

    // 2. Notification to team (if NOTIFY_EMAIL set)
    if (NOTIFY_EMAIL) {
      await sendEmail({
        to: NOTIFY_EMAIL,
        subject: `New AlignPod order from ${full_name}`,
        html: adminEmailHtml({ full_name, email, phone, quantity, delivery_address, notes }),
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function sendEmail({ to, subject, html }: { to: string; subject: string; html: string }) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "AlignEye <orders@aligneye.com>",
      to,
      subject,
      html,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Resend error ${res.status}: ${text}`);
  }
}

function customerEmailHtml({ full_name, quantity }: { full_name: string; quantity: number }) {
  return `
<!DOCTYPE html>
<html>
<body style="font-family:sans-serif;background:#f9fafb;padding:40px 0;">
  <div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;padding:40px;box-shadow:0 2px 16px rgba(0,0,0,0.07);">
    <h1 style="font-size:22px;color:#0f172a;margin-bottom:4px;">Hi ${full_name} 👋</h1>
    <p style="color:#475569;font-size:15px;line-height:1.6;">
      We've received your request for <strong>${quantity} AlignPod${quantity > 1 ? "s" : ""}</strong>.
      Our team will reach out within <strong>24 hours</strong> to confirm availability, pricing, and delivery details.
    </p>
    <div style="margin:28px 0;padding:20px;background:#f8f5ff;border-radius:12px;border-left:4px solid #9333ea;">
      <p style="margin:0;color:#6b21a8;font-size:14px;font-weight:600;">What happens next?</p>
      <p style="margin:8px 0 0;color:#7c3aed;font-size:14px;line-height:1.5;">
        We'll contact you on the email or phone number you provided to walk you through payment and shipping.
      </p>
    </div>
    <p style="color:#94a3b8;font-size:13px;margin-top:32px;">
      — Team AlignEye<br/>
      <a href="https://aligneye.com" style="color:#9333ea;text-decoration:none;">aligneye.com</a>
    </p>
  </div>
</body>
</html>`;
}

function adminEmailHtml(data: {
  full_name: string;
  email: string;
  phone?: string;
  quantity: number;
  delivery_address?: string;
  notes?: string;
}) {
  return `
<!DOCTYPE html>
<html>
<body style="font-family:sans-serif;background:#f9fafb;padding:40px 0;">
  <div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;padding:40px;box-shadow:0 2px 16px rgba(0,0,0,0.07);">
    <h2 style="color:#0f172a;font-size:20px;">New AlignPod Order Request</h2>
    <table style="width:100%;border-collapse:collapse;margin-top:16px;">
      ${row("Name", data.full_name)}
      ${row("Email", data.email)}
      ${row("Phone", data.phone ?? "—")}
      ${row("Quantity", String(data.quantity))}
      ${row("Address", data.delivery_address ?? "—")}
      ${row("Notes", data.notes ?? "—")}
    </table>
  </div>
</body>
</html>`;
}

function row(label: string, value: string) {
  return `<tr>
    <td style="padding:10px 0;color:#64748b;font-size:14px;width:120px;border-bottom:1px solid #f1f5f9;">${label}</td>
    <td style="padding:10px 0;color:#0f172a;font-size:14px;border-bottom:1px solid #f1f5f9;">${value}</td>
  </tr>`;
}
