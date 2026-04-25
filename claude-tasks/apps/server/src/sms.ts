import twilio from "twilio";

const sid = process.env.TWILIO_ACCOUNT_SID;
const token = process.env.TWILIO_AUTH_TOKEN;
const from = process.env.TWILIO_FROM;
const to = process.env.OWNER_PHONE;

const client = sid && token ? twilio(sid, token) : null;

export async function sendSms(body: string): Promise<void> {
  if (!client || !from || !to) {
    console.log(`[sms:dev] would send to ${to ?? "?"}: ${body}`);
    return;
  }
  await client.messages.create({ from, to, body });
}

export function smsConfigured(): boolean {
  return client !== null && !!from && !!to;
}
