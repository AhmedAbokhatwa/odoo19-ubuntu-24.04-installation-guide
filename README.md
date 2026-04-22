<kbd><a href="README.ar.md">🇸🇦 اقرأ بالعربية</a></kbd>
# 🚀 Odoo 19 Installer — Ubuntu 24.04 LTS
> Install a production-ready Odoo 19 in minutes.
> **Python 3.11 · PostgreSQL · Nginx (optional) · SSL (optional)**

---

## ⚡ Quick Install

```bash
chmod +x install-odoo19.sh
sudo bash install-odoo19.sh
```

The script will prompt you for all required values — no editing needed.

---

## 📋 What the Script Configures

| Variable | Default | Description |
|---|---|---|
| System user | `odoo19` | Dedicated OS user for Odoo |
| Install path | `/opt/odoo19` | Base directory |
| Odoo version | `19.0` | Git branch to clone |
| HTTP port | `8069` | Odoo listening port |
| Master password | *(prompted)* | Odoo database manager password |
| DB password | *(prompted)* | PostgreSQL user password |
| Workers | `4` | Odoo worker processes |
| Nginx | *(optional)* | Reverse proxy setup |
| Domain + SSL | *(optional)* | Let's Encrypt certificate |

---

## 🛠️ Manual Installation

Follow these steps if you prefer to install manually or want to understand what the script does.

### Prerequisites

- Ubuntu 24.04 LTS (64-bit)
- Root or sudo access
- At least 2 GB RAM, 20 GB disk

---

### Step 1 — Update System & Install Dependencies

```bash
sudo apt-get update && sudo apt-get upgrade -y

sudo apt-get install -y \
    python3.11 python3.11-venv python3.11-dev \
    build-essential libpq-dev libxml2-dev libxslt1-dev \
    libldap2-dev libsasl2-dev libssl-dev libjpeg-dev \
    zlib1g-dev libffi-dev node-less npm nodejs \
    wget curl postgresql
```

---

### Step 2 — Install Node.js 22 & rtlcss

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo npm install -g rtlcss
```

---

### Step 3 — Install wkhtmltopdf (patched build)

```bash
sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -y ./wkhtmltox_0.12.6.1-3.jammy_amd64.deb
```

> ⚠️ Use this specific patched build — the Ubuntu package does not support headers/footers in PDF reports.

---

### Step 4 — PostgreSQL Setup

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Create Odoo DB user (replace YOUR_PASSWORD)
sudo -u postgres psql -c "CREATE USER odoo19 WITH CREATEDB NOSUPERUSER NOCREATEROLE PASSWORD 'YOUR_PASSWORD';"
```

---

### Step 5 — Create System User & Directories

```bash
sudo adduser --system --home /opt/odoo19 --group odoo19

sudo mkdir -p /opt/odoo19/odoo-custom-addons
sudo mkdir -p /var/log/odoo19

sudo chown -R odoo19:odoo19 /opt/odoo19 /var/log/odoo19
```

---

### Step 6 — Clone Odoo 19

```bash
sudo -u odoo19 git clone https://github.com/odoo/odoo.git \
    --depth 1 --branch 19.0 /opt/odoo19/odoo
```

---

### Step 7 — Python 3.11 Virtual Environment

```bash
sudo -u odoo19 python3.11 -m venv /opt/odoo19/odoo-venv

# Verify Python version inside venv
sudo -u odoo19 /opt/odoo19/odoo-venv/bin/python --version
# Expected: Python 3.11.x
```

> ❌ Do **not** use Python 3.10 — Odoo 19 pins `Babel==2.9.1` for Python < 3.11 which is incompatible with Odoo 19's internal pytz monkeypatch.

---

### Step 8 — Install Python Dependencies

```bash
sudo -u odoo19 bash -c "
    source /opt/odoo19/odoo-venv/bin/activate && \
    pip install --upgrade pip setuptools wheel && \
    pip install -r /opt/odoo19/odoo/requirements.txt
"
```

> This step compiles gevent, lxml, and psycopg2 from source. It takes 5–15 minutes.

---

### Step 9 — Odoo Configuration File

```bash
sudo nano /etc/odoo19.conf
```

```ini
[options]
admin_passwd = YOUR_MASTER_PASSWORD
db_host = localhost
db_port = 5432
db_user = odoo19
db_password = YOUR_DB_PASSWORD
db_name = False
addons_path = /opt/odoo19/odoo/addons,/opt/odoo19/odoo-custom-addons
logfile = /var/log/odoo19/odoo19.log
log_level = info
xmlrpc_port = 8069
workers = 4
max_cron_threads = 2
list_db = True
proxy_mode = False
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
```

```bash
sudo chown odoo19:odoo19 /etc/odoo19.conf
sudo chmod 640 /etc/odoo19.conf
```

---

### Step 10 — Systemd Service

```bash
sudo nano /etc/systemd/system/odoo19.service
```

```ini
[Unit]
Description=Odoo 19
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo19
User=odoo19
Group=odoo19
ExecStart=/opt/odoo19/odoo-venv/bin/python /opt/odoo19/odoo/odoo-bin -c /etc/odoo19.conf
StandardOutput=journal+console
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable odoo19
sudo systemctl start odoo19

# Verify
sudo systemctl status odoo19
```

---

### Step 11 — Nginx Reverse Proxy (Optional)

```bash
sudo apt-get install -y nginx
sudo nano /etc/nginx/sites-available/odoo19
```

```nginx
upstream odoo19 {
    server 127.0.0.1:8069;
}

server {
    listen 80;
    server_name erp.example.com;

    proxy_read_timeout    720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout    720s;

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    location / {
        proxy_pass http://odoo19;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering   on;
        proxy_pass        http://odoo19;
    }

    gzip on;
    gzip_types text/css text/plain application/javascript application/json;
}
```

```bash
sudo ln -s /etc/nginx/sites-available/odoo19 /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

For SSL, add `proxy_mode = True` to `/etc/odoo19.conf`, then:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d erp.example.com
```

---

## 🔧 Useful Commands

```bash
# Service control
sudo systemctl start|stop|restart|status odoo19

# Live logs
sudo journalctl -u odoo19 -f

# Odoo log file
sudo tail -f /var/log/odoo19/odoo19.log

# Update a module
sudo -u odoo19 /opt/odoo19/odoo-venv/bin/python \
    /opt/odoo19/odoo/odoo-bin -c /etc/odoo19.conf \
    -u my_module -d my_database --stop-after-init

# Test config manually (without systemd)
sudo -u odoo19 /opt/odoo19/odoo-venv/bin/python \
    /opt/odoo19/odoo/odoo-bin -c /etc/odoo19.conf
```

---

## 🔐 Security Checklist

- [ ] Change master password immediately after first login
- [ ] Set `list_db = False` in config for production
- [ ] Never expose port 8069 directly — use Nginx
- [ ] Enable firewall: `sudo ufw allow 22,80,443/tcp && sudo ufw enable`
- [ ] Schedule regular PostgreSQL backups: `pg_dump -U odoo19 mydb > backup.sql`

---

## 🐛 Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Babel/pytz ImportError` | Wrong Python version | Use Python 3.11, not 3.10 |
| `psycopg2` build fails | Missing `libpq-dev` | `sudo apt install libpq-dev` |
| `gevent` build fails | Old pip/setuptools | `pip install --upgrade pip setuptools wheel` |
| Permission denied | Wrong file ownership | `sudo chown -R odoo19:odoo19 /opt/odoo19` |
| Port 8069 refused | Service not running | `sudo systemctl status odoo19` |
| DB connection error | Wrong password in config | Check `db_password` in `/etc/odoo19.conf` |
| apt GPG errors | Broken third-party repos | `sudo rm -f /etc/apt/sources.list.d/*microsoft*` |

---

## 📁 File Structure

```
/opt/odoo19/
├── odoo/                  # Odoo source code (git)
├── odoo-venv/             # Python 3.11 virtual environment
└── odoo-custom-addons/    # Your custom modules

/etc/odoo19.conf           # Main configuration file
/var/log/odoo19/           # Log files
/etc/systemd/system/odoo19.service
```

---

## 📄 License

MIT — free to use, modify, and distribute.
