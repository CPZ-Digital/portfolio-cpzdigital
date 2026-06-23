-- Assistente CPZ Digital — Schema Supabase
-- Execute em: Supabase → SQL Editor → New query → Cole tudo → Run

-- ── Tabela de conversas ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS conversations (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id   TEXT        NOT NULL,                    -- chatId do Tawk.to ou senderId do Instagram
  channel      TEXT        NOT NULL,                    -- 'tawkto' | 'instagram' | 'whatsapp'
  sender       TEXT        NOT NULL,                    -- 'visitor' | 'assistente'
  message      TEXT        NOT NULL,
  visitor_name TEXT,                                    -- nome do visitante (quando disponível)
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para buscas rápidas
CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_channel ON conversations(channel);
CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at DESC);

-- ── View: resumo de sessões ───────────────────────────────────────────────────
-- Útil para ver todas as conversas de um jeito organizado
CREATE OR REPLACE VIEW v_sessions AS
SELECT
  session_id,
  channel,
  MAX(visitor_name)                                     AS visitor_name,
  MIN(created_at)                                       AS started_at,
  MAX(created_at)                                       AS last_message_at,
  COUNT(*) FILTER (WHERE sender = 'visitor')            AS visitor_messages,
  COUNT(*) FILTER (WHERE sender = 'assistente')         AS assistant_messages,
  COUNT(*)                                              AS total_messages
FROM conversations
GROUP BY session_id, channel
ORDER BY last_message_at DESC;

-- ── RLS (Row Level Security) ──────────────────────────────────────────────────
-- Habilita RLS para proteger os dados
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Permite que o backend (usando a anon key) insira registros
-- Em produção, troque para service_role key no backend para mais segurança
CREATE POLICY "backend pode inserir" ON conversations
  FOR INSERT WITH CHECK (true);

-- Permite leitura apenas com autenticação (você no painel do Supabase)
CREATE POLICY "somente autenticados leem" ON conversations
  FOR SELECT USING (auth.role() = 'authenticated');
