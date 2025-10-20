# 🚀 Sample Flask App for Automated Deployment

This is a simple Flask web application used for testing automated deployments with Bash, Docker, and EC2.

## How It Works
The app runs a basic web server on port 5000 and displays a simple message:
> "🚀 Hello from Betty's automated deployment app!"

## Files
- `app.py` → Flask web app
- `Dockerfile` → Defines how the app is containerized
- `README.md` → Documentation

## Run Locally
```bash
docker build -t sample-app .
docker run -d -p 5000:5000 sample-app
