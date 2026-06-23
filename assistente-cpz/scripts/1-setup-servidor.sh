#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# SCRIPT 1 — Setup do servidor Oracle Cloud (Ubuntu 22.04 ARM)
# Execute UMA VEZ logo após criar o servidor
# Como usar: bash 1-setup-servidor.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e  # para se qualquer comando falhar

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Assistente CPZ — Setup do Servidor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Atualiza o sistema
echo "[1/7] Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

# 2. Instala Node.js 20 (LTS)
echo "[2/7] Instalando Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 3. Instala PM2 (gerenciador de processos — mantém o app rodando)
echo "[3/7] Instalando PM2..."
sudo npm install -g pm2

# 4. Instala Nginx (proxy reverso)
echo "[4/7] Instalando Nginx..."
sudo apt install -y nginx

# 5. Instala Certbot (SSL grátis via Let's Encrypt)
echo "[5/7] Instalando Certbot..."
sudo apt install -y certbot python3-certbot-nginx

# 6. Instala Git
echo "[6/7] Instalando Git..."
sudo apt install -y git

# 7. Configura firewall
echo "[7/7] Configurando firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

echo ""
echo "✓ Servidor configurado com sucesso!"
echo ""
echo "PRÓXIMO PASSO: Execute o script 2-deploy-app.sh"
echo "  Antes, copie os arquivos do assistente-cpz/backend para o servidor:"
echo "  scp -r ./assistente-cpz/backend ubuntu@SEU_IP_ORACLE:/home/ubuntu/assistente-cpz"
