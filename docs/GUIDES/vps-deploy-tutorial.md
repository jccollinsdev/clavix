# Clavis VPS Deployment Tutorial

End-to-end guide to deploy the Clavis backend to a DigitalOcean droplet with Cloudflare Tunnel and automated GitHub Actions deploys.

---

## Overview

| Component | Role |
|---|---|
| DigitalOcean droplet | Runs Docker containers |
| Docker Compose | Manages `clavis-backend` container |
| Cloudflare Tunnel | Exposes backend to the internet securely |
| GitHub Actions | Syncs code + restarts stack on every push to `main` |

Public URL: `https://clavis.andoverdigital.com`

---

## Step 1 — Create the Droplet

On DigitalOcean:

- **Image**: Ubuntu 24.04 LTS
- **Plan**: Basic, 2 GB RAM minimum (4 GB recommended)
- **Disk**: 40–50 GB SSD
- **Auth**: SSH key only (no password)
- **Hostname**: `clavis-prod`

After creation, note the IP. The current production IP is `134.122.114.241`.

---

## Step 2 — Bootstrap the Server

SSH in as root:

```bash
ssh root@<droplet-ip>
```

Install base packages and create the deploy user:

```bash
apt update && apt install -y ca-certificates curl git ufw

adduser clavis
usermod -aG sudo clavis

ufw allow OpenSSH
ufw enable
```

Install Docker and the Compose plugin:

```bash
curl -fsSL https://get.docker.com | sh
apt install -y docker-compose-plugin
usermod -aG docker clavis
```

Log out and reconnect as `clavis` so group memberships apply:

```bash
exit
ssh clavis@<droplet-ip>
```

---

## Step 3 — Create the Deploy Directory

```bash
mkdir -p /opt/clavis/backend/apns
```

This path is required before GitHub Actions runs for the first time.

---

## Step 4 — Copy Secrets to the VPS

Secrets are **never** committed to git. Copy them manually once:

```bash
# From your local machine
scp backend/.env clavis@<droplet-ip>:/opt/clavis/backend/.env
scp backend/apns/apns.p8 clavis@<droplet-ip>:/opt/clavis/backend/apns/apns.p8
```

Then lock the permissions on the VPS:

```bash
chmod 600 /opt/clavis/backend/.env /opt/clavis/backend/apns/apns.p8
```

Required env vars in `/opt/clavis/backend/.env`:

```
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_JWT_SECRET=
MINIMAX_API_KEY=
MINIMAX_BASE_URL=
FINNHUB_API_KEY=
POLYGON_API_KEY=
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_KEY_PATH=/app/apns/apns.p8
APNS_BUNDLE_ID=com.clavisdev.portfolioassistant
ADMIN_PASSWORD=
```

---

## Step 5 — Add GitHub Actions Secrets

In your GitHub repo go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|---|---|
| `PROD_SSH_HOST` | `134.122.114.241` (or your droplet IP) |
| `PROD_SSH_USER` | `clavix-backend` |
| `PROD_SSH_KEY` | Private key that matches the SSH key on the VPS |

The deploy workflow (`.github/workflows/deploy-prod.yml`) uses these to rsync code and restart the stack on every push to `main`.

---

## Step 6 — Set Up the SSH Key for GitHub Actions

On your local machine, generate a dedicated deploy key:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/clavis_deploy_ed25519
```

Copy the **public** key to the VPS:

```bash
ssh-copy-id -i ~/.ssh/clavis_deploy_ed25519.pub clavis@<droplet-ip>
```

Paste the **private** key (`~/.ssh/clavis_deploy_ed25519`) into the `PROD_SSH_KEY` GitHub secret.

> The existing VPS uses the key at `~/.ssh/clavix_vps_ed25519`. Use that if it is already authorised.

---

## Step 7 — First Manual Deploy

Before GitHub Actions takes over, do one manual deploy to confirm the stack works:

```bash
# On the VPS
cd /opt/clavis

# Clone the repo (first time only)
git clone https://github.com/<your-org>/clavis.git .

docker compose up -d --build
docker compose ps
```

Verify the backend is running locally on the VPS:

```bash
curl http://127.0.0.1:8000/health
# Expected: {"status":"ok"}
```

---

## Step 8 — Install Cloudflare Tunnel

On the VPS:

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb
```

Authenticate and use your existing tunnel token (from Cloudflare dashboard → Zero Trust → Tunnels → `clavis-prod` → Configure):

```bash
cloudflared tunnel login
cloudflared tunnel run clavis-prod
```

Or, if you have a tunnel credentials file, place it at `/etc/cloudflared/clavis-prod.json` and create a systemd service:

```bash
sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel for Clavis
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel run clavis-prod
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared
sudo systemctl status cloudflared
```

The tunnel should route `https://clavis.andoverdigital.com` → `http://127.0.0.1:8000`.

---

## Step 9 — Verify End-to-End

```bash
# Public health check
curl https://clavis.andoverdigital.com/health
# Expected: {"status":"ok"}

# Docker containers running
docker compose ps

# Backend logs look clean
docker logs clavis-backend-1 --tail 50
```

Check the admin dashboard:

```
https://clavis.andoverdigital.com/admin
```

Login with `ADMIN_PASSWORD` from `.env`.

---

## Step 10 — Set Up Uptime Monitoring

On [UptimeRobot](https://uptimerobot.com) (free tier):

| Field | Value |
|---|---|
| Monitor type | HTTP(s) |
| URL | `https://clavis.andoverdigital.com/health` |
| Method | GET |
| Check interval | 5 minutes |
| Expected status | 200 |
| Alert contact | Your email |

Name it `Clavis API Health`.

---

## Automated Deploys (GitHub Actions)

The workflow at `.github/workflows/deploy-prod.yml` runs on every push to `main`:

1. rsync the repo to `/opt/clavis/` (excludes `.git`, `ios/`, secrets)
2. SSH in and run `docker compose up -d --build --remove-orphans`
3. Polls `/health` up to 10 times — fails the workflow if it never returns 200

No action is needed on your part. Just merge to `main`.

---

## Day-2 Operations

### Check what's running

```bash
ssh -i ~/.ssh/clavix_vps_ed25519 clavix-backend@134.122.114.241
docker compose ps
```

### View live logs

```bash
docker logs clavis-backend-1 --tail 100 -f
```

### Restart only the backend

```bash
cd /opt/clavis
docker compose up -d --build backend
```

### Update a secret

```bash
# Edit on the VPS directly
nano /opt/clavis/backend/.env
docker restart clavis-backend-1
```

### Full stack restart

```bash
cd /opt/clavis
docker compose down && docker compose up -d --build
```

---

## Security Checklist

- [ ] Ports 8000 and 8001 are NOT open to the internet (UFW blocks them)
- [ ] Cloudflare tunnel is the only public entry point
- [ ] `.env` and `apns.p8` have `chmod 600`
- [ ] No secrets are committed to git
- [ ] SSH password login is disabled (key only)
