# HNG DevOps Intern Stage 1 - Automated Deployment Script

A production-grade Bash script that automates the deployment of Dockerized applications to remote Linux servers with comprehensive error handling, logging, and idempotent operations.

## 🚀 Features

- **Automated Deployment**: Full CI/CD pipeline simulation
- **Docker Support**: Built-in Docker and Docker Compose support
- **Nginx Reverse Proxy**: Automatic reverse proxy configuration
- **Comprehensive Logging**: Detailed timestamped logging
- **Error Handling**: Robust error handling with meaningful exit codes
- **Idempotent Operations**: Safe to run multiple times
- **Cleanup Functionality**: Complete resource cleanup option

## 📋 Prerequisites

### Local Machine
- Bash 4.0+
- Git
- SSH client
- SCP (for file transfer)

### Remote Server
- Ubuntu/Debian Linux
- SSH access with key-based authentication
- Sudo privileges for deployment user

## 🛠️ Usage

### Basic Deployment
```bash
# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh

Cleanup Deployment
bash
# Remove all deployed resources
./deploy.sh --cleanup

📝 Deployment Process
The script performs the following steps:

Parameter Collection: Interactive input for deployment configuration

SSH Validation: Tests connection to remote server

Repository Management: Clones or updates Git repository with PAT authentication

Remote Environment Setup: Installs and configures Docker, Docker Compose, and Nginx

Application Deployment: Transfers files, builds, and runs Docker containers

Nginx Configuration: Sets up reverse proxy on port 80

Validation: Comprehensive deployment validation checks

🔧 Configuration Parameters
When running the script, you'll be prompted for:

Git Repository URL: Your application's Git repository

Personal Access Token (PAT): For repository authentication

Branch Name: Deployment branch (default: main)

Remote Server Details: Username, IP address, SSH key path

Application Port: Internal container port

Project Name: Identifier for your deployment

🐳 Supported Application Types
Dockerfile: Single-container applications

docker-compose.yml: Multi-container applications

📊 Logging

The script creates detailed logs in deploy_YYYYMMDD.log format with:

Timestamped entries

Success/failure status

Error messages and exit codes

Deployment validation results

🛡️ Error Handling
Exit Codes: Meaningful codes for each deployment stage

Validation: Comprehensive input validation

Graceful Failure: Clean error messages and safe termination

Automatic Cleanup: Resource cleanup on script interruption

🔄 Idempotency
The script is designed to be safely re-runable:

Graceful container stop/removal before deployment

Prevention of duplicate Nginx configurations

Safe handling of existing resources

🌐 Deployment Architecture
text
User Local Machine → Remote Linux Server
                             │
                             ├── Docker Container (Your App)
                             ├── Nginx (Reverse Proxy)
                             └── System Services (Docker, Nginx)
🧪 Testing
After deployment, your application will be accessible at:

text
http://YOUR_SERVER_IP
🐛 Troubleshooting
Common Issues
SSH Connection Failed

Verify SSH key permissions: chmod 600 your-key.pem

Check server accessibility and security groups

Repository Access Denied

Verify PAT has correct repository permissions

Check repository URL format

Docker Build Failed

Check Dockerfile syntax and dependencies

Verify build context

Logs Location
Deployment logs: deploy_YYYYMMDD.log

Container logs: sudo docker logs PROJECT_NAME

Nginx logs: /var/log/nginx/

📞 Support
For issues with this deployment script, check:

Deployment logs for specific error messages

Container status: sudo docker ps

Nginx configuration: sudo nginx -t

📄 License
This project is part of the HNG DevOps Internship Stage 1 Task.

HNG DevOps Internship | HNG Tech | HNG Hire | HNG Internship


