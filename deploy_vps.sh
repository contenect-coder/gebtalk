#!/usr/bin/env bash
# ==============================================================================
# GEBTALK Automated VPS Deployment Script
# Tested on Ubuntu 22.04 / 24.04 LTS (Oracle Cloud Always Free / DigitalOcean / etc.)
# ==============================================================================

set -e

echo "=========================================================="
echo " Starting GEBTALK VPS Automated Setup"
echo "=========================================================="

# 1. Prompt for Domain and Email if not provided in environment
if [ -z "$DOMAIN" ]; then
    read -p "Enter your DuckDNS domain (e.g., gebtalk.duckdns.org): " DOMAIN
fi

if [ -z "$SSL_EMAIL" ]; then
    read -p "Enter your email for SSL alerts (e.g., yourname@gmail.com): " SSL_EMAIL
fi

echo ">> Configuring for domain: $DOMAIN"
echo ">> SSL Alert Email: $SSL_EMAIL"

# 2. Update and install prerequisites
echo ">> Updating system packages and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv git nginx certbot python3-certbot-nginx curl ufw

# 3. Configure Ubuntu firewall (iptables & ufw)
echo ">> Opening firewall ports 80, 443, and 22..."
# Oracle Cloud Ubuntu images often include strict iptables rules by default:
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT || true
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT || true
sudo netfilter-persistent save || true

# Also configure UFW if active:
sudo ufw allow 22/tcp || true
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true
sudo ufw status || true

# 4. Create App Directory and Clone / Pull Repository
APP_DIR="/var/www/gebtalk"
echo ">> Setting up application directory at $APP_DIR..."
sudo mkdir -p $APP_DIR
sudo chown -R $USER:$USER $APP_DIR

if [ -d "$APP_DIR/.git" ]; then
    echo ">> Updating existing repository..."
    cd $APP_DIR
    git fetch origin
    git reset --hard origin/main
else
    echo ">> Cloning repository..."
    git clone https://github.com/contenect-coder/gebtalk.git $APP_DIR
    cd $APP_DIR
fi

# 5. Set up Python Virtual Environment
echo ">> Setting up Python virtual environment..."
cd $APP_DIR/gebtalk_backend
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 6. Configure Environment File (.env)
echo ">> Setting up .env configuration..."
cat << 'EOF' > $APP_DIR/gebtalk_backend/.env
SUPABASE_DB_URL=postgresql://postgres:company4me.comapp@db.pkzsorkvyyqxpvbqcpei.supabase.co:5432/postgres
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=frankvictorcls@gmail.com
SMTP_PASS=cdzwvterrmililwr
EMAIL_FROM=GEBTALK <frankvictorcls@gmail.com>
TEXTBEE_API_KEY=6ccb72f2-68bf-485f-8ebd-58203c3728d2
TEXTBEE_DEVICE_ID=6a33fc6477015dcde1195750
FRONTEND_BASE_URL=https://gebtalk-app.netlify.app
EOF

# Ensure uploads directory exists
mkdir -p $APP_DIR/gebtalk_backend/uploads
chmod 755 $APP_DIR/gebtalk_backend/uploads

# 7. Create Systemd Service for Gunicorn
echo ">> Creating systemd background service (gebtalk.service)..."
sudo bash -c "cat << EOF > /etc/systemd/system/gebtalk.service
[Unit]
Description=GEBTALK Flask API Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR/gebtalk_backend
Environment=\"PATH=$APP_DIR/gebtalk_backend/venv/bin\"
ExecStart=$APP_DIR/gebtalk_backend/venv/bin/gunicorn app:app --bind 127.0.0.1:5000 --workers 3 --threads 4 --timeout 120
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable gebtalk.service
sudo systemctl restart gebtalk.service

# 8. Configure Nginx Reverse Proxy
echo ">> Configuring Nginx reverse proxy..."
sudo bash -c "cat << EOF > /etc/nginx/sites-available/gebtalk
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_read_timeout 120s;
    }
}
EOF"

sudo ln -sf /etc/nginx/sites-available/gebtalk /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# 9. Obtain SSL Certificate with Certbot
echo ">> Obtaining free Let's Encrypt SSL certificate for $DOMAIN..."
sudo certbot --nginx --non-interactive --agree-tos --email "$SSL_EMAIL" -d "$DOMAIN" --redirect || {
    echo "Warning: Certbot SSL setup failed. Verify that $DOMAIN correctly resolves to this server's public IP."
}

echo "=========================================================="
echo " GEBTALK Backend Deployment Complete!"
echo " URL: https://$DOMAIN/api"
echo " Health check: https://$DOMAIN/api/health"
echo "=========================================================="
