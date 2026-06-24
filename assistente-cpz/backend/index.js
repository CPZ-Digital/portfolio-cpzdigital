require('dotenv').config();
const express = require('express');
const Groq = require('groq-sdk');
const { createClient } = require('@supabase/supabase-js');
const axios = require('axios');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());

// CORS — permite requisições do site cpzdigital.com e localhost
app.use((req, res, next) => {
  const allowed = ['https://cpzdigital.com.br', 'https://www.cpzdigital.com.br', 'https://cpzdigital.com', 'https://www.cpzdigital.com', 'http://localhost'];
  const origin = req.headers.origin;
  if (!origin || allowed.some(o => origin.startsWith(o))) {
    res.setHeader('Access-Control-Allow-Origin', origin || '*');
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

// ── Clientes externos ──────────────────────────────────────────────────────────
const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

const SYSTEM_PROMPT = fs.readFileSync(path.join(__dirname, 'prompts', 'system.txt'), 'utf8');

// Histórico em memória por sessão (limpa ao reiniciar — ok para conversas curtas)
const sessionHistory = new Map();
const MAX_HISTORY = 10; // pares de mensagens

// ── Helper: chama Groq (Llama 3.3 70B) e mantém histórico ────────────────────
async function getAIResponse(sessionId, userMessage) {
  const history = sessionHistory.get(sessionId) || [];

  const messages = [
    { role: 'system', content: SYSTEM_PROMPT },
    ...history,
    { role: 'user', content: userMessage },
  ];

  const completion = await groq.chat.completions.create({
    model: 'llama-3.3-70b-versatile',
    messages,
    max_tokens: 500,
    temperature: 0.7,
  });

  const reply = completion.choices[0].message.content;

  // Atualiza histórico e limita tamanho
  history.push({ role: 'user', content: userMessage });
  history.push({ role: 'assistant', content: reply });
  if (history.length > MAX_HISTORY * 2) history.splice(0, 2);
  sessionHistory.set(sessionId, history);

  return reply;
}

// ── Helper: salva conversa no Supabase ────────────────────────────────────────
async function saveMessages(sessionId, channel, visitorMsg, assistantMsg, visitorName = null) {
  await supabase.from('conversations').insert([
    { session_id: sessionId, sender: 'visitor', message: visitorMsg, channel, visitor_name: visitorName },
    { session_id: sessionId, sender: 'assistente', message: assistantMsg, channel },
  ]);
}

// ── ROTA PRINCIPAL — Widget customizado do site ───────────────────────────────
app.post('/chat', async (req, res) => {
  const { message, sessionId } = req.body;
  if (!message || !sessionId) return res.status(400).json({ error: 'message e sessionId obrigatórios' });

  try {
    const reply = await getAIResponse(sessionId, message);
    await saveMessages(sessionId, 'site', message, reply);
    res.json({ reply });
  } catch (err) {
    console.error('[Chat] Erro:', err.message);
    res.status(500).json({ reply: 'Desculpe, tive um problema técnico. Tente novamente em instantes.' });
  }
});

// ── TAWK.TO WEBHOOK ───────────────────────────────────────────────────────────
// Configure em: Tawk.to → Administration → Integrations → Webhooks
// URL: https://SEU_DOMINIO/webhook/tawkto
// Eventos: chat:incoming_message
app.post('/webhook/tawkto', async (req, res) => {
  res.sendStatus(200); // responde imediatamente (Tawk.to exige < 5s)

  const { event, chatId, visitor, message } = req.body;

  // Só processa mensagens de visitantes
  if (event !== 'chat:incoming_message') return;
  if (!message?.text) return;
  if (message.sender?.type === 'agent') return; // ignora mensagens do próprio bot

  try {
    const reply = await getAIResponse(chatId, message.text);

    // Envia resposta via Tawk.to REST API
    const credentials = Buffer.from(
      `${process.env.TAWKTO_EMAIL}:${process.env.TAWKTO_API_KEY}`
    ).toString('base64');

    await axios.post(
      `https://rest.tawk.to/v3/chats/${chatId}/messages`,
      { type: 'msg', msg: reply },
      {
        headers: {
          Authorization: `Basic ${credentials}`,
          'Content-Type': 'application/json',
        },
      }
    );

    await saveMessages(chatId, 'tawkto', message.text, reply, visitor?.name);
  } catch (err) {
    console.error('[Tawk.to] Erro:', err.response?.data || err.message);
  }
});

// ── INSTAGRAM WEBHOOK — verificação ──────────────────────────────────────────
// Configure em: Meta for Developers → Webhooks → Instagram → messages
// URL: https://SEU_DOMINIO/webhook/instagram
app.get('/webhook/instagram', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === process.env.INSTAGRAM_VERIFY_TOKEN) {
    console.log('[Instagram] Webhook verificado.');
    return res.status(200).send(challenge);
  }
  res.sendStatus(403);
});

// ── INSTAGRAM WEBHOOK — mensagens ─────────────────────────────────────────────
app.post('/webhook/instagram', async (req, res) => {
  res.sendStatus(200);

  const body = req.body;
  if (body.object !== 'instagram') return;

  for (const entry of body.entry || []) {
    for (const event of entry.messaging || []) {
      if (!event.message?.text || event.message.is_echo) continue;

      const senderId = event.sender.id;
      const userMsg = event.message.text;

      try {
        const reply = await getAIResponse(senderId, userMsg);

        await axios.post(
          `https://graph.facebook.com/v19.0/me/messages`,
          { recipient: { id: senderId }, message: { text: reply } },
          { params: { access_token: process.env.INSTAGRAM_ACCESS_TOKEN } }
        );

        await saveMessages(senderId, 'instagram', userMsg, reply);
      } catch (err) {
        console.error('[Instagram] Erro:', err.response?.data || err.message);
      }
    }
  }
});

// ── HEALTH CHECK ──────────────────────────────────────────────────────────────
app.get('/health', (_req, res) =>
  res.json({ status: 'ok', uptime: process.uptime(), time: new Date() })
);

// ── START ─────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Assistente CPZ rodando na porta ${PORT}`);
  console.log(`Health: http://localhost:${PORT}/health`);
});
