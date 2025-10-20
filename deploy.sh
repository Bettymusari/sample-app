#!/bin/bash

# =============================
# DevOps Stage 1 Automated Deployment Script
# Author: Betty Musari
# =============================

# Exit immediately if a command fails
set -e
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Log setup
LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "🚀 Starting Automated Deployment..."

# -----------------------------
# Step 1: Collect Parameters
# -----------------------------
read -p "Enter Git repository URL: " GIT_REPO
read -p "Enter branch name [default: main]: " BRANCH
BRANCH=${BRANCH:-main}
read -p "Enter remote server username [e.g. ubuntu]: " SSH_USER
read -p "Enter remote server IP address: " SSH_IP
read -p "Enter path to your SSH key (e.g. ~/.ssh/hng-key2.pem): " SSH_KEY
read -p "Enter application port: " APP_PORT

REMOTE_DIR="~/sample-app"

echo "✅ Parameters collected."

# -----------------------------
# Step 2: Clone or Update Repo
# -----------------------------
if [ -d "sample-app" ]; then
    echo "📂 sample-app exists, pulling latest changes..."
    cd sample-app
    git pull origin $BRANCH
    cd ..
else
    echo "📂 Cloning repository..."
    git clone -b $BRANCH $GIT_REPO sample-app
fi

# -----------------------------
# Step 3: SSH & Prepare Remote
# -----------------------------
echo "🔑 Connecting to remote server $SSH_USER@$SSH_IP..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$SSH_IP "bash -s" <<'ENDSSH'

# Exit immediately on error
set -e

# Update & upgrade
sudo apt update -y
sudo apt upgrade -y || true

# -----------------------------
# Docker Installation (safe)
# -----------------------------
sudo apt remove -y containerd || true
sudo apt remove -y docker docker-engine docker.io docker-ce docker-ce-cli || true
sudo apt autoremove -y

sudo apt install -y ca-certificates curl gnupg lsb-release

# Docker GPG & repo (fixed for non-interactive)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

# -----------------------------
# Nginx Installation
# -----------------------------
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

ENDSSH

echo "✅ Remote environment ready."

# -----------------------------
# Step 4: Deploy App
# -----------------------------
echo "🚀 Deploying application to remote server..."
scp -i "$SSH_KEY" -r sample-app/* $SSH_USER@$SSH_IP:$REMOTE_DIR/

ssh -i "$SSH_KEY" $SSH_USER@$SSH_IP "bash -s" <<ENDSSH2
set -e
cd $REMOTE_DIR

# Remove old container if exists
sudo docker rm -f sample-app || true

# Build & run container
sudo docker build -t sample-app .
sudo docker run -d --name sample-app -p $APP_PORT:$APP_PORT sample-app

# -----------------------------
# Nginx Reverse Proxy
# -----------------------------
NGINX_CONF="/etc/nginx/sites-available/sample-app"
sudo tee \$NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/sample-app
sudo nginx -t
sudo systemctl reload nginx

# -----------------------------
# Validation
# -----------------------------
sudo systemctl status docker
sudo docker ps
curl -I http://localhost

ENDSSH2

echo "✅ Deployment completed successfully!"
echo "Your app should now be accessible via: http://$SSH_IP"
echo "Logs saved to $LOGFILE"
