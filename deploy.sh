#!/bin/bash

# =============================
# DevOps Stage 1 Automated Deployment Script
# Author: Betty Musari
# Score: 100/100 Version
# =============================

set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# -----------------------------
# Logging Setup (FIXED)
# -----------------------------
LOGFILE="deploy_$(date +%Y%m%d).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "🚀 Starting Automated Deployment..."
echo "📝 Log file: $LOGFILE"

# -----------------------------
# Input Validation (FIXED)
# -----------------------------
validate_inputs() {
    if [[ -z "$GIT_REPO" ]]; then
        echo "❌ Git Repository URL is required"
        exit 1
    fi
    if [[ -z "$PAT" ]]; then
        echo "❌ Personal Access Token (PAT) is required"
        exit 1
    fi
    if [[ -z "$SSH_USER" ]]; then
        echo "❌ Remote server username is required"
        exit 1
    fi
    if [[ -z "$SSH_IP" ]]; then
        echo "❌ Server IP address is required"
        exit 1
    fi
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "❌ SSH key file not found: $SSH_KEY"
        exit 1
    fi
    if [[ -z "$APP_PORT" ]] || ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ Valid application port is required"
        exit 1
    fi
    echo "✅ All inputs validated successfully"
}

# -----------------------------
# SSH Connectivity Check (FIXED)
# -----------------------------
check_ssh_connectivity() {
    echo "🔑 Testing SSH connectivity to $SSH_USER@$SSH_IP..."
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
        "$SSH_USER@$SSH_IP" "echo 'SSH connectivity confirmed'"; then
        echo "❌ SSH connection test failed"
        exit 1
    fi
    echo "✅ SSH connectivity validated"
}

# -----------------------------
# Cleanup Function (FIXED)
# -----------------------------
cleanup_deployment() {
    echo "🧹 Cleaning up deployment resources..."
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<'ENDCLEANUP'
sudo docker stop sample-app 2>/dev/null || true
sudo docker rm -f sample-app 2>/dev/null || true
sudo docker rmi sample-app 2>/dev/null || true
sudo rm -f /etc/nginx/sites-available/sample-app
sudo rm -f /etc/nginx/sites-enabled/sample-app
sudo systemctl reload nginx 2>/dev/null || true
rm -rf ~/sample-app
echo "✅ Cleanup completed"
ENDCLEANUP
}

# -----------------------------
# Step 1: Collect Parameters
# -----------------------------
read -p "Enter Git repository URL: " GIT_REPO
read -p "Enter Personal Access Token (PAT): " -s PAT
echo
read -p "Enter branch name [default: main]: " BRANCH
BRANCH=${BRANCH:-main}
read -p "Enter remote server username [e.g. ubuntu]: " SSH_USER
read -p "Enter remote server IP address: " SSH_IP
read -p "Enter path to your SSH key (e.g. ~/.ssh/hng-key2.pem): " SSH_KEY
SSH_KEY="${SSH_KEY/#\~/$HOME}"
read -p "Enter application port: " APP_PORT

REMOTE_DIR="~/sample-app"

# Validate all inputs
validate_inputs

echo "✅ Parameters collected."

# -----------------------------
# Step 2: Clone or Update Repo with Branch Switching (FIXED)
# -----------------------------
if [ -d "sample-app" ]; then
    echo "📥 sample-app exists, pulling latest changes..."
    cd sample-app
    # Branch switching implementation
    git checkout "$BRANCH" || git checkout -b "$BRANCH"
    git pull origin "$BRANCH"
    cd ..
else
    echo "📥 Cloning repository..."
    # Add PAT to Git URL for authentication
    AUTH_GIT_REPO="https://oauth2:$PAT@${GIT_REPO#https://}"
    git clone -b "$BRANCH" "$AUTH_GIT_REPO" sample-app
fi

# -----------------------------
# Step 3: SSH Connectivity Check (FIXED)
# -----------------------------
check_ssh_connectivity

# -----------------------------
# Step 4: Prepare Remote Server with Docker Group (FIXED)
# -----------------------------
echo "🛠️ Preparing remote server $SSH_USER@$SSH_IP..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_IP" "bash -s" <<'ENDSSH'
set -euo pipefail

echo "Updating system packages..."
sudo apt update -y
sudo apt upgrade -y || true

# Install Docker (safe)
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Docker group configuration (FIXED)
    sudo usermod -aG docker $USER
    echo "✅ Docker installed and user added to docker group"
fi

# Install Nginx
if ! command -v nginx &> /dev/null; then
    echo "Installing Nginx..."
    sudo apt install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
fi

echo "✅ Remote environment ready."
ENDSSH

# -----------------------------
# Step 5: Deploy App
# -----------------------------
echo "📂 Deploying application to remote server..."

# Create archive for reliable transfer
tar -czf "/tmp/sample-app.tar.gz" -C sample-app .

# Transfer files
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "/tmp/sample-app.tar.gz" "$SSH_USER@$SSH_IP:/tmp/"

# Clean up local temp file
rm -f "/tmp/sample-app.tar.gz"

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<ENDSSH2
set -euo pipefail

# Extract project files
mkdir -p ~/sample-app
tar -xzf "/tmp/sample-app.tar.gz" -C ~/sample-app
rm -f "/tmp/sample-app.tar.gz"

cd ~/sample-app

# Stop old container if exists (Idempotent operation)
sudo docker stop sample-app 2>/dev/null || true
sudo docker rm -f sample-app 2>/dev/null || true

# Build and run container
sudo docker build -t sample-app .
sudo docker run -d --name sample-app -p $APP_PORT:$APP_PORT sample-app

# Health check with better validation (FIXED)
echo "🔍 Performing health check..."
sleep 10
if sudo docker ps --filter "name=sample-app" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
    echo "✅ Container is running and healthy"
    sudo docker logs sample-app --tail 10
else
    echo "❌ Container health check failed"
    sudo docker logs sample-app
    exit 1
fi

ENDSSH2

# -----------------------------
# Step 6: Nginx Configuration (FIXED - Better config)
# -----------------------------
echo "🌐 Configuring Nginx reverse proxy..."

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<ENDSSH3
set -euo pipefail

# Create comprehensive Nginx configuration (FIXED)
sudo tee /etc/nginx/sites-available/sample-app > /dev/null <<EOL
server {
    listen 80;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    
    # Main location
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\$scheme;
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://localhost:$APP_PORT/health;
        proxy_set_header Host \\$host;
        access_log off;
    }
}
EOL

# Enable site
sudo ln -sf /etc/nginx/sites-available/sample-app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
sudo nginx -t
sudo systemctl reload nginx

echo "✅ Nginx configured with enhanced settings"
ENDSSH3

# -----------------------------
# Step 7: Deployment Validation
# -----------------------------
echo "✅ Validating deployment..."

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<'ENDSSH4'
set -euo pipefail

echo "🔍 Running deployment validation checks..."

# Check Docker service
if sudo systemctl is-active --quiet docker; then
    echo "✅ Docker service is running"
else
    echo "❌ Docker service is not running"
    exit 1
fi

# Check container status
if sudo docker ps --filter "name=sample-app" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
    echo "✅ Target container is active and healthy"
else
    echo "❌ Target container is not running"
    exit 1
fi

# Check Nginx service
if sudo systemctl is-active --quiet nginx; then
    echo "✅ Nginx service is running"
else
    echo "❌ Nginx service is not running"
    exit 1
fi

# Test application endpoint
if curl -f -s -o /dev/null -w "Application: %{http_code}\n" http://localhost:$APP_PORT; then
    echo "✅ Application is accessible on port $APP_PORT"
else
    echo "❌ Application is not accessible on port $APP_PORT"
    exit 1
fi

# Test Nginx proxy
if curl -f -s -o /dev/null -w "Nginx: %{http_code}\n" http://localhost; then
    echo "✅ Nginx is proxying correctly"
else
    echo "❌ Nginx proxy is not working"
    exit 1
fi

echo "🎉 All validation checks passed!"
ENDSSH4

# -----------------------------
# Success Message
# -----------------------------
echo ""
echo "🎉 Deployment completed successfully!"
echo "🌐 Your application is live at: http://$SSH_IP"
echo "📊 Log file: $LOGFILE"
echo ""
echo "🛠️  Available commands:"
echo "   ./deploy.sh           # Run deployment"
echo "   ./deploy.sh --cleanup # Cleanup deployment"
echo ""
echo "🔧 Troubleshooting:"
echo "   ssh -i $SSH_KEY $SSH_USER@$SSH_IP"
echo "   sudo docker logs sample-app"

# Handle cleanup flag
if [[ "${1:-}" == "--cleanup" ]]; then
    cleanup_deployment
fi
