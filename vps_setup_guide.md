# Hostinger VPS Backend Deployment Guide

This guide walks you through setting up a Hostinger VPS (running Ubuntu 22.04 / 24.04 LTS) to host only the backend Node.js server. 

> [!NOTE]
> The Flutter mobile applications (player and partner apps) will be built locally on your machine. You do **not** need to upload any Flutter/app files to the VPS server.

---

## 1. Initial VPS Server Setup & SSH Access

### Log in to the VPS
Log in to your VPS from your terminal using the root credentials provided by Hostinger:
```bash
ssh root@YOUR_SERVER_IP
```

### Update the System Packages
Make sure the server package list is up-to-date:
```bash
sudo apt update && sudo apt upgrade -y
```

---

## 2. Installing Prerequisites

We need to install Node.js, PostgreSQL, Redis, PM2, and Nginx.

### A. Install Node.js & npm
We will use NodeSource to install Node.js v20 (LTS):
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```
Verify the installation:
```bash
node -v
npm -v
```

### B. Install PostgreSQL Database
Install PostgreSQL:
```bash
sudo apt install postgresql postgresql-contrib -y
```

Start and enable the PostgreSQL service:
```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

Set up a database and user:
1. Log in to the PostgreSQL prompt:
   ```bash
   sudo -i -u postgres psql
   ```
2. Create the database and user (replace `yourpassword` with a strong password):
   ```sql
   CREATE DATABASE athelete;
   CREATE USER athlete_user WITH PASSWORD 'yourpassword';
   GRANT ALL PRIVILEGES ON DATABASE athelete TO athlete_user;
   ALTER DATABASE athelete OWNER TO athlete_user;
   ```
3. Exit PostgreSQL:
   ```sql
   \q
   ```

### C. Install Redis Cache
Install and start Redis:
```bash
sudo apt install redis-server -y
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

### D. Install PM2 (Process Manager)
PM2 runs your Node.js application in the background and restarts it if the server reboots:
```bash
sudo npm install -y -g pm2
```

---

## 3. Pulling the Code from GitHub (Private Repository)

Since your repository is private, we will use a **GitHub Deploy Key** to clone the code securely without credentials.

### Step 1: Generate an SSH Key on the VPS
Generate a new SSH key pair:
```bash
ssh-keygen -t ed25519 -C "vps-deploy-key"
```
*Press Enter to accept defaults (leave passphrase empty for automatic pulls).*

### Step 2: Retrieve the Public Key
Print the generated public key to your screen:
```bash
cat ~/.ssh/id_ed25519.pub
```
Copy the printed output (starts with `ssh-ed25519 ...`).

### Step 3: Add the Deploy Key to GitHub
1. Go to your repository on GitHub.
2. Navigate to **Settings** > **Deploy keys**.
3. Click **Add deploy key**.
4. Give it a title (e.g., `Hostinger-VPS-Backend`).
5. Paste your public key into the key field.
6. Leave "Allow write access" **unchecked** (read-only is safer).
7. Click **Add key**.

### Step 4: Clone the Repository
Now you can clone the repository using SSH:
```bash
cd /var/www
# Replace with your actual repository SSH URL:
git clone git@github.com:USERNAME/REPO_NAME.git athlete-backend
cd athlete-backend
```

---

## 4. Environment and Dependency Setup

### Install Dependencies
Install the Node.js production and development modules:
```bash
npm install
```

### Configure Environment Variables
Create the production environment file:
```bash
nano .env
```

Paste and adjust the following configurations:
```ini
PORT=4000
DATABASE_URL="postgresql://athlete_user:yourpassword@localhost:5432/athelete?schema=public"
REDIS_URL="redis://localhost:6379"
JWT_SECRET="generate_a_long_random_jwt_secret_string"
NODE_ENV="production"
```
*Save and close the file (`Ctrl + O`, `Enter`, then `Ctrl + X`).*

### Push the Database Schema
Execute Prisma to create the database tables:
```bash
npx prisma db push
```

---

## 5. Build & Start the Backend

### Compile TypeScript
Build the application:
```bash
npm run build
```

### Start the Application with PM2
Launch the compiled backend:
```bash
pm2 start dist/index.js --name "athlete-backend"
```

### Configure PM2 to Auto-Start on System Boot
Ensure the backend starts automatically if the VPS restarts:
```bash
pm2 startup
```
*Copy the command printed in the terminal output and run it as root.*

Now save the PM2 configuration state:
```bash
pm2 save
```

---

## 6. Configuring Nginx & SSL (Reverse Proxy)

We will use Nginx to map traffic from port 80/443 (HTTP/HTTPS) to your Node application on port 4000, and handle WebSockets.

### Install Nginx
```bash
sudo apt install nginx -y
```

### Set up Nginx Server Block
Create a new configuration file (replace `yourdomain.com` with your domain name or use server IP):
```bash
sudo nano /etc/nginx/sites-available/athlete
```

Paste the following configuration:
```nginx
server {
    listen 80;
    server_name yourdomain.com; # Replace with domain or VPS IP

    # Backend API Endpoints
    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # WebSocket connection upgrade (CRITICAL for live updates)
    location /ws {
        proxy_pass http://localhost:4000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Uploads folder (Static Files)
    location /uploads/ {
        alias /var/www/athlete-backend/uploads/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
```
*Save and close the file.*

### Enable the Configuration and Restart Nginx
```bash
sudo ln -s /etc/nginx/sites-available/athlete /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default # Remove default site if conflict
sudo nginx -t # Test syntax
sudo systemctl restart nginx
```

---

## 7. Set Up Free SSL (Let's Encrypt)

If you have a domain pointed to your Hostinger VPS, you can install free SSL certificates in seconds:

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d yourdomain.com
```
*Follow the on-screen instructions to finish SSL setup. Certbot will automatically rewrite the Nginx config to support HTTPS (`https://yourdomain.com`).*

---

## 8. Updating the Backend Code in the Future

Whenever you push new backend updates to GitHub:
```bash
cd /var/www/athlete-backend
git pull
npm install
npm run build
npx prisma db push # If there are schema changes
pm2 restart athlete-backend
```
