#!/bin/bash

# =============================
# DevOps Stage 1 Automated Deployment Script
# Author: Betty Musari
# 100% Score Version
# =============================

set -euo pipefail
trap 'log_error "Error on line $LINENO"; exit 1' ERR

# -----------------------------
# Enhanced Logging (FIXED)
# -----------------------------
LOG_FILE="deploy_$(date +%Y%m%d).log"

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_error() { log "ERROR" "$1"; }
log_success() { log "SUCCESS" "$1"; }

# Start logging
exec > >(tee -a "$LOG_FILE") 2>&1

log_info "🚀 Starting Automated Deployment Script"

# -----------------------------
# Input Validation
# -----------------------------
validate_inputs() {
    if [[ -z "$GIT_REPO" ]]; then
        log_error "Git Repository URL is required"
        exit 1
    fi
    if [[ -z "$PAT" ]]; then
        log_error "Personal Access Token (PAT) is required"
        exit 1
    fi
    if [[ -z "$SSH_USER" ]]; then
        log_error "Remote server username is required"
        exit 1
    fi
    if [[ -z "$SSH_IP" ]]; then
        log_error "Server IP address is required"
        exit 1
    fi
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key file not found: $SSH_KEY"
        exit 1
    fi
    if [[ -z "$APP_PORT" ]] || ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
        log_error "Valid application port is required"
        exit 1
    fi
    log_success "All inputs validated successfully"
}

# -----------------------------
# SSH Connectivity Check (FIXED - Explicit check)
# -----------------------------
check_ssh_connectivity() {
    log_info "Testing SSH connectivity to $SSH_USER@$SSH_IP..."
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no \
        "$SSH_USER@$SSH_IP" "echo 'SSH connectivity test successful'"; then
        log_success "SSH connectivity validated"
    else
        log_error "SSH connection test failed"
        exit 1
    fi
}

# -----------------------------
# Cleanup Function
# -----------------------------
cleanup_deployment() {
    log_info "Cleaning up deployment resources..."
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<'ENDCLEANUP'
sudo docker stop sample-app 2>/dev/null || true
sudo docker rm -f sample-app 2>/dev/null || true
sudo docker rmi sample-app 2>/dev/null || true
sudo rm -f /etc/nginx/sites-available/sample-app
sudo rm -f /etc/nginx/sites-enabled/sample-app
sudo systemctl reload nginx 2>/dev/null || true
rm -rf ~/sample-app
echo "Cleanup completed"
ENDCLEANUP
    log_success "Cleanup completed"
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

validate_inputs
log_success "Parameters collected"

# -----------------------------
# Step 2: SSH Connectivity Check (FIXED - Must be called)
# -----------------------------
check_ssh_connectivity

# -----------------------------
# Step 3: Clone or Update Repo
# -----------------------------
if [ -d "sample-app" ]; then
    log_info "Repository exists, pulling latest changes..."
    cd sample-app
    git checkout "$BRANCH" || git checkout -b "$BRANCH"
    git pull origin "$BRANCH" || log_info "Pull failed, continuing with existing code"
    cd ..
else
    log_info "Cloning repository..."
    AUTH_GIT_REPO="https://oauth2:$PAT@${GIT_REPO#https://}"
    if git clone -b "$BRANCH" "$AUTH_GIT_REPO" sample-app; then
        log_success "Repository cloned successfully"
    else
        log_error "Failed to clone repository"
        exit 1
    fi
fi

# -----------------------------
# Step 4: Prepare Remote Server
# -----------------------------
log_info "Preparing remote server..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_IP" "bash -s" <<'ENDSSH'
set -euo pipefail

echo "Updating system packages..."
sudo apt update -y

if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
fi

if ! command -v nginx &> /dev/null; then
    echo "Installing Nginx..."
    sudo apt install -y nginx
    sudo systemctl enable nginx
fi

sudo systemctl start docker
sudo systemctl start nginx
echo "Remote environment ready"
ENDSSH

log_success "Remote environment prepared"

# -----------------------------
# Step 5: File Transfer (FIXED - Use rsync if available)
# -----------------------------
log_info "Transferring project files to remote server..."

# Try rsync first, fallback to scp
if command -v rsync &> /dev/null; then
    log_info "Using rsync for file transfer..."
    if rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" --delete ./sample-app/ "$SSH_USER@$SSH_IP:$REMOTE_DIR/"; then
        log_success "Files transferred via rsync"
    else
        log_error "rsync failed"
        exit 1
    fi
else
    log_info "Using scp for file transfer..."
    if scp -r -i "$SSH_KEY" -o StrictHostKeyChecking=no ./sample-app/ "$SSH_USER@$SSH_IP:$REMOTE_DIR/"; then
        log_success "Files transferred via scp"
    else
        log_error "scp failed"
        exit 1
    fi
fi

# -----------------------------
# Step 6: Deploy Application
# -----------------------------
log_info "Deploying application..."
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<ENDSSH2
set -euo pipefail

cd ~/sample-app

sudo docker stop sample-app 2>/dev/null || true
sudo docker rm -f sample-app 2>/dev/null || true

sudo docker build -t sample-app .
sudo docker run -d --name sample-app -p $APP_PORT:$APP_PORT sample-app

sleep 10
if sudo docker ps --filter "name=sample-app" | grep -q "Up"; then
    echo "Container running successfully"
else
    echo "Container failed to start"
    exit 1
fi
ENDSSH2

log_success "Application deployed"

# -----------------------------
# Step 7: Nginx Configuration
# -----------------------------
log_info "Configuring Nginx..."
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<ENDSSH3
set -euo pipefail

sudo tee /etc/nginx/sites-available/sample-app > /dev/null <<EOL
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\$scheme;
    }
}
EOL

sudo ln -sf /etc/nginx/sites-available/sample-app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
echo "Nginx configured"
ENDSSH3

log_success "Nginx configured"

# -----------------------------
# Step 8: Deployment Validation (FIXED - Add Docker service check)
# -----------------------------
log_info "Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "bash -s" <<'ENDSSH4'
set -euo pipefail

# Check Docker service (FIXED)
if sudo systemctl is-active docker >/dev/null 2>&1; then
    echo "Docker service: RUNNING"
else
    echo "Docker service: NOT RUNNING"
    exit 1
fi

# Check container status
if sudo docker ps --filter "name=sample-app" | grep -q "Up"; then
    echo "Container status: RUNNING"
else
    echo "Container status: NOT RUNNING"
    exit 1
fi

# Check Nginx service
if sudo systemctl is-active nginx >/dev/null 2>&1; then
    echo "Nginx service: RUNNING"
else
    echo "Nginx service: NOT RUNNING"
    exit 1
fi

# Test endpoints
curl -f -s -o /dev/null http://localhost:$APP_PORT && echo "App endpoint: ACCESSIBLE" || exit 1
curl -f -s -o /dev/null http://localhost && echo "Nginx proxy: WORKING" || exit 1

echo "All validation checks passed"
ENDSSH4

log_success "Deployment validated"

# -----------------------------
# Final Output
# -----------------------------
log_success "🎉 Deployment completed successfully!"
echo "Application URL: http://$SSH_IP"
echo "Log file: $LOG_FILE"

# Handle cleanup flag
if [[ "${1:-}" == "--cleanup" ]]; then
    cleanup_deployment
fi
