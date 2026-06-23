# Assistente CPZ — Guia Completo de Instalação

IA de atendimento da CPZ Digital. Zero custo mensal. Responde no site (Tawk.to) e Instagram Direct.

**Stack:** Node.js + Gemini 1.5 Flash (grátis) + Supabase (grátis) + Oracle Cloud (grátis sempre)

---

## Pré-requisitos — Contas a criar (todas gratuitas)

| Serviço | Link | Para quê |
|---------|------|----------|
| Google AI Studio | https://aistudio.google.com | Chave da API Gemini |
| Supabase | https://supabase.com | Banco de dados das conversas |
| Oracle Cloud | https://cloud.oracle.com | Servidor gratuito para hospedar |
| Tawk.to | https://tawk.to | Widget de chat no site |
| Meta for Developers | https://developers.facebook.com | Instagram Direct |

---

## PASSO 1 — Gemini API (5 minutos)

1. Acesse https://aistudio.google.com/app/apikey
2. Clique em **Create API key**
3. Copie a chave — vai para o `.env` como `GEMINI_API_KEY`

**Limite gratuito:** 1.500 requisições/dia, 1M tokens/minuto. Mais que suficiente.

---

## PASSO 2 — Supabase (10 minutos)

1. Crie conta em https://supabase.com
2. Crie um novo projeto (escolha região: South America)
3. Vá em **SQL Editor → New query**
4. Cole o conteúdo de `supabase/schema.sql` e clique em **Run**
5. Vá em **Settings → API** e copie:
   - `URL` → `SUPABASE_URL` no `.env`
   - `anon public` key → `SUPABASE_ANON_KEY` no `.env`

---

## PASSO 3 — Tawk.to (10 minutos)

1. Crie conta em https://tawk.to
2. Crie uma nova propriedade com o nome "CPZ Digital"
3. Copie o **Widget Code** que aparece na tela
4. No arquivo `index.html`, substitua `PROPERTY_ID` e `WIDGET_ID` pelos valores reais
5. Vá em **Administration → REST API** e copie a API Key
   - `TAWKTO_EMAIL` = seu email do Tawk.to
   - `TAWKTO_API_KEY` = a chave gerada
6. Configure o Webhook:
   - Administration → Integrations → Webhooks
   - URL: `https://SEU_DOMINIO/webhook/tawkto`
   - Eventos: marque `chat:incoming_message`

---

## PASSO 4 — Oracle Cloud Free Tier (30 minutos)

### 4.1 — Criar o servidor
1. Acesse https://cloud.oracle.com e crie conta (pede cartão mas não cobra)
2. Vá em **Compute → Instances → Create Instance**
3. Configure:
   - **Name:** assistente-cpz
   - **Image:** Ubuntu 22.04
   - **Shape:** VM.Standard.A1.Flex (ARM — Always Free)
   - **OCPUs:** 2 | **Memory:** 12 GB
4. Baixe a **SSH key** quando solicitado
5. Clique em **Create**

### 4.2 — Abrir portas no firewall da Oracle
1. Vá em **Networking → Virtual Cloud Networks → seu VCN → Security Lists**
2. Adicione regras de Ingress para:
   - Porta 80 (HTTP)
   - Porta 443 (HTTPS)

### 4.3 — Apontar domínio (ou usar IP direto)
- No seu provedor de domínio, crie um registro A: `assistente.cpzdigital.com` → IP do servidor Oracle
- Aguarde propagação (5-30 minutos)

### 4.4 — Setup do servidor
```bash
# Conecte via SSH
ssh -i sua-chave.key ubuntu@IP_DO_SERVIDOR

# Baixe e execute o script de setup
wget https://raw.githubusercontent.com/.../1-setup-servidor.sh
bash 1-setup-servidor.sh
```

Ou copie o arquivo `scripts/1-setup-servidor.sh` para o servidor e execute.

---

## PASSO 5 — Deploy do app (15 minutos)

### 5.1 — Copie os arquivos para o servidor
```bash
# No seu computador (PowerShell/Terminal):
scp -r -i sua-chave.key ./assistente-cpz/backend ubuntu@IP_DO_SERVIDOR:/home/ubuntu/assistente-cpz
```

### 5.2 — Configure as variáveis de ambiente
```bash
# No servidor:
cd /home/ubuntu/assistente-cpz
cp .env.example .env
nano .env   # preencha todas as chaves
```

### 5.3 — Execute o deploy
```bash
bash /home/ubuntu/scripts/2-deploy-app.sh assistente.cpzdigital.com
```

### 5.4 — Teste
```bash
curl https://assistente.cpzdigital.com/health
# Deve retornar: {"status":"ok",...}
```

---

## PASSO 6 — Instagram Direct (20 minutos)

1. Acesse https://developers.facebook.com
2. Crie um App → tipo **Business**
3. Adicione o produto **Instagram Graph API**
4. Configure Webhooks:
   - URL de callback: `https://assistente.cpzdigital.com/webhook/instagram`
   - Token de verificação: `cpz_digital_webhook_2026` (ou o que você colocou no `.env`)
   - Inscreva no evento: `messages`
5. Gere um **Page Access Token** de longa duração
   - Cole no `.env` como `INSTAGRAM_ACCESS_TOKEN`

---

## Estrutura de arquivos

```
assistente-cpz/
├── backend/
│   ├── index.js              ← servidor principal
│   ├── package.json
│   ├── .env.example          ← copie para .env e preencha
│   └── prompts/
│       └── system.txt        ← personalidade da Cris
├── supabase/
│   └── schema.sql            ← rode no SQL Editor do Supabase
├── scripts/
│   ├── 1-setup-servidor.sh   ← rode UMA VEZ no Oracle Cloud
│   └── 2-deploy-app.sh       ← rode para fazer deploy
└── README.md                 ← este arquivo
```

---

## Manutenção

**Ver logs do app:**
```bash
pm2 logs assistente-cpz
```

**Reiniciar após editar system.txt:**
```bash
pm2 restart assistente-cpz
```

**Ver conversas no Supabase:**
- Supabase → Table Editor → conversations
- Ou use a view `v_sessions` para ver resumo por sessão

**Atualizar base de conhecimento:**
- Edite `backend/prompts/system.txt` no servidor
- Rode `pm2 restart assistente-cpz`

---

## Custos

| Item | Custo |
|------|-------|
| Oracle Cloud (servidor) | R$ 0 — Always Free |
| Gemini 1.5 Flash API | R$ 0 — até 1.500 req/dia |
| Supabase | R$ 0 — free tier (500MB) |
| Tawk.to | R$ 0 — plano gratuito |
| Meta/Instagram API | R$ 0 |
| SSL (Let's Encrypt) | R$ 0 |
| **Total mensal** | **R$ 0,00** |
