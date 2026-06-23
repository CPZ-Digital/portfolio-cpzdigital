#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# SCRIPT 2 — Deploy do Assistente CPZ no servidor
# Execute no servidor Oracle Cloud, dentro da pasta do app
# Como usar: bash 2-deploy-app.sh SEU_DOMINIO.com
# ─────────────────────────────────────────────────────────────────────────────

set -e

DOMINIO=${1:-"assistente.cpzdigital.com"}
APP_DIR="/home/ubuntu/assistente-cpz"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Deploy: $DOMINIO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Instala dependências Node
echo "[1/5] Instalando dependências..."
cd "$APP_DIR"
npm install --omit=dev

# 2. Cria .env se não existir
if [ ! -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  echo ""
  echo "⚠ Arquivo .env criado. EDITE-O antes de continuar:"
  echo "  nano $APP_DIR/.env"
  echo ""
  echo "Pressione ENTER quando terminar de preencher o .env..."
  read -r
fi

# 3. Inicia com PM2
echo "[2/5] Iniciando app com PM2..."
pm2 delete assistente-cpz 2>/dev/null || true
pm2 start "$APP_DIR/index.js" --name assistente-cpz
pm2 save
pm2 startup systemd -u ubuntu --hp /home/ubuntu | tail -1 | sudo bash

# 4. Configura Nginx
echo "[3/5] Configurando Nginx..."
sudo tee /etc/nginx/sites-available/assistente-cpz > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMINIO;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/assistente-cpz /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 5. SSL com Let's Encrypt
echo "[4/5] Configurando SSL..."
echo "IMPORTANTE: Certifique-se que o domínio $DOMINIO aponta para o IP deste servidor."
echo "Pressione ENTER para continuar com o SSL..."
read -r
sudo certbot --nginx -d "$DOMINIO" --non-interactive --agree-tos --email adriano.cpaz16@gmail.com

echo "[5/5] Verificando status..."
pm2 status
sudo systemctl status nginx --no-pager

echo ""
echo "✓ Deploy concluído!"
echo ""
echo "Endpoints disponíveis:"
echo "  https://$DOMINIO/health"
echo "  https://$DOMINIO/webhook/tawkto   ← configure no Tawk.to"
echo "  https://$DOMINIO/webhook/instagram ← configure no Meta for Developers"
