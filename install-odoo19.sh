#!/usr/bin/env bash
# ============================================================
#  Odoo 19 Automated Installer — Ubuntu 24.04 LTS
#  Python 3.11 | PostgreSQL | Nginx (optional)
# ============================================================
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}══ $* ${NC}"; }

# ── Root check ──────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script as root: sudo bash $0"

# ============================================================
#  STEP 1 — Collect user variables
# ============================================================
step "Configuration"

echo -e "${BOLD}Welcome to the Odoo 19 Installer for Ubuntu 24.04 LTS${NC}"
echo "Please enter the following values (press Enter to accept defaults):"
echo ""

# Odoo system user
read -rp "  Odoo system user         [default: odoo19]: " ODOO_USER
ODOO_USER="${ODOO_USER:-odoo19}"

# Install directory
read -rp "  Install base directory   [default: /opt/${ODOO_USER}]: " ODOO_BASE
ODOO_BASE="${ODOO_BASE:-/opt/${ODOO_USER}}"

# Odoo git branch
read -rp "  Odoo version/branch      [default: 19.0]: " ODOO_VERSION
ODOO_VERSION="${ODOO_VERSION:-19.0}"

# Odoo HTTP port
read -rp "  Odoo HTTP port           [default: 8069]: " ODOO_PORT
ODOO_PORT="${ODOO_PORT:-8069}"

# Master password
while true; do
    read -rsp "  Odoo master password     : " ODOO_MASTER_PASS; echo
    read -rsp "  Confirm master password  : " ODOO_MASTER_PASS2; echo
    [[ "$ODOO_MASTER_PASS" == "$ODOO_MASTER_PASS2" ]] && break
    warn "Passwords do not match. Try again."
done

# DB password
while true; do
    read -rsp "  PostgreSQL user password : " DB_PASS; echo
    read -rsp "  Confirm DB password      : " DB_PASS2; echo
    [[ "$DB_PASS" == "$DB_PASS2" ]] && break
    warn "Passwords do not match. Try again."
done

# Workers
read -rp "  Odoo workers             [default: 4]: " ODOO_WORKERS
ODOO_WORKERS="${ODOO_WORKERS:-4}"

# Nginx
read -rp "  Install Nginx reverse proxy? [y/N]: " SETUP_NGINX
SETUP_NGINX="${SETUP_NGINX:-n}"

DOMAIN_NAME=""
if [[ "${SETUP_NGINX,,}" == "y" ]]; then
    read -rp "  Domain name (e.g. erp.example.com): " DOMAIN_NAME
    [[ -z "$DOMAIN_NAME" ]] && error "Domain name required for Nginx setup."
fi

# SSL
SETUP_SSL="n"
if [[ "${SETUP_NGINX,,}" == "y" ]]; then
    read -rp "  Setup SSL with Let's Encrypt? [y/N]: " SETUP_SSL
    SETUP_SSL="${SETUP_SSL:-n}"
fi

# Derived paths
ODOO_HOME="${ODOO_BASE}"
ODOO_SRC="${ODOO_HOME}/odoo"
ODOO_VENV="${ODOO_HOME}/odoo-venv"
ODOO_ADDONS="${ODOO_HOME}/odoo-custom-addons"
ODOO_CONF="/etc/${ODOO_USER}.conf"
ODOO_LOG_DIR="/var/log/${ODOO_USER}"
ODOO_LOG="${ODOO_LOG_DIR}/${ODOO_USER}.log"
SERVICE_NAME="${ODOO_USER}"

echo ""
echo -e "${BOLD}Summary:${NC}"
echo "  System user    : ${ODOO_USER}"
echo "  Install path   : ${ODOO_HOME}"
echo "  Odoo version   : ${ODOO_VERSION}"
echo "  HTTP port      : ${ODOO_PORT}"
echo "  Workers        : ${ODOO_WORKERS}"
echo "  Nginx          : ${SETUP_NGINX}"
[[ "${SETUP_NGINX,,}" == "y" ]] && echo "  Domain         : ${DOMAIN_NAME}"
echo ""
read -rp "Proceed with installation? [Y/n]: " CONFIRM
[[ "${CONFIRM,,}" == "n" ]] && { info "Aborted."; exit 0; }

# ============================================================
#  STEP 2 — System update & dependencies
# ============================================================
step "Updating system packages"
rm -f /etc/apt/sources.list.d/*microsoft* 2>/dev/null || true
sudo apt --fix-broken install -y || true
sudo apt-get update || true
sudo apt-get upgrade -y || true
# apt-get update -qq || true || true
# apt-get upgrade -y -qq || true
success "System updated"

step "Installing system dependencies"
sudo apt-get install -y \
    python3.11 python3.11-venv python3.11-dev \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libsasl2-dev \
    libssl-dev \
    libjpeg-dev \
    zlib1g-dev \
    build-essential \
    node-less \
    npm \
    nodejs \
    wget \
    curl \
    postgresql || true

success "System dependencies installed"

step "Installing Node.js 22"

curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
success "Node.js installed"

step "Installing rtlcss"
sudo npm install -g rtlcss
success "rtlcss installed"



step "Installing wkhtmltopdf (patched version)"

sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -y ./wkhtmltox_0.12.6.1-3.jammy_amd64.deb || true
success "wkhtmltopdf installed"
# ============================================================
#  STEP 3 — PostgreSQL
# ============================================================
step "Configuring PostgreSQL"
systemctl enable postgresql --quiet
systemctl start postgresql

# Create DB user if not exists
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${ODOO_USER}'" | grep -q 1; then
    warn "PostgreSQL user '${ODOO_USER}' already exists — skipping creation"
else
    sudo -u postgres psql -c "CREATE USER ${ODOO_USER} WITH CREATEDB NOSUPERUSER NOCREATEROLE PASSWORD '${DB_PASS}';"
    success "PostgreSQL user '${ODOO_USER}' created"
fi

# ============================================================
#  STEP 4 — Odoo system user
# ============================================================
step "Creating system user"
if id "${ODOO_USER}" &>/dev/null; then
    warn "System user '${ODOO_USER}' already exists — skipping"
else
    adduser --system --home "${ODOO_HOME}" --group "${ODOO_USER}"
    success "System user '${ODOO_USER}' created"
fi

# ============================================================
#  STEP 5 — Directory structure
# ============================================================
step "Creating directory structure"
mkdir -p "${ODOO_ADDONS}" "${ODOO_LOG_DIR}"
chown -R "${ODOO_USER}:${ODOO_USER}" "${ODOO_HOME}" "${ODOO_LOG_DIR}"
success "Directories created"

# ============================================================
#  STEP 6 — Clone Odoo
# git clone https://www.github.com/odoo/odoo --depth 1 --branch 19.0 /opt/odoo19/odoo
# ============================================================
step "Cloning Odoo ${ODOO_VERSION}"
if [[ -d "${ODOO_SRC}/.git" ]]; then
    warn "Odoo source already exists at ${ODOO_SRC} — skipping clone"
else
    sudo -u "${ODOO_USER}" git clone \
        https://github.com/odoo/odoo.git \
        --depth 1 --branch "${ODOO_VERSION}" \
        "${ODOO_SRC}"
    success "Odoo cloned to ${ODOO_SRC}"
fi

# ============================================================
#  STEP 7 — Python virtual environment
# ============================================================
step "Creating Python 3.11 virtual environment"
if [[ -f "${ODOO_VENV}/bin/python" ]]; then
    warn "Virtual environment already exists — skipping"
else
    sudo -u "${ODOO_USER}" python3.11 -m venv "${ODOO_VENV}"
    success "Virtual environment created"
fi

# Verify Python version
PYTHON_VER=$(sudo -u "${ODOO_USER}" "${ODOO_VENV}/bin/python" --version 2>&1)
info "Virtual environment Python: ${PYTHON_VER}"
echo "${PYTHON_VER}" | grep -q "3.11" || error "Expected Python 3.11 in venv but got: ${PYTHON_VER}"

# ============================================================
#  STEP 8 — Install Python dependencies
# ============================================================
step "Installing Python dependencies (this may take 5-15 minutes)"
sudo -u "${ODOO_USER}" bash -c "
    source '${ODOO_VENV}/bin/activate' && \
    pip install --upgrade pip setuptools wheel --quiet && \
    pip install -r '${ODOO_SRC}/requirements.txt' --quiet
"
success "Python dependencies installed"

# ============================================================
#  STEP 9 — Odoo config file
# ============================================================
step "Writing Odoo configuration"
cat > "${ODOO_CONF}" <<EOF
[options]
admin_passwd = ${ODOO_MASTER_PASS}
db_host = localhost
db_port = 5432
db_user = ${ODOO_USER}
db_password = ${DB_PASS}
db_name = False
addons_path = ${ODOO_SRC}/addons,${ODOO_ADDONS}
logfile = ${ODOO_LOG}
log_level = info
xmlrpc_port = ${ODOO_PORT}
workers = ${ODOO_WORKERS}
max_cron_threads = 2
list_db = True
proxy_mode = $([ "${SETUP_NGINX,,}" == "y" ] && echo "True" || echo "False")
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
EOF

chown "${ODOO_USER}:${ODOO_USER}" "${ODOO_CONF}"
chmod 640 "${ODOO_CONF}"
success "Config written to ${ODOO_CONF}"

# ============================================================
#  STEP 10 — Systemd service
# ============================================================
step "Creating systemd service"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Odoo ${ODOO_VERSION} (${ODOO_USER})
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
SyslogIdentifier=${SERVICE_NAME}
User=${ODOO_USER}
Group=${ODOO_USER}
ExecStart=${ODOO_VENV}/bin/python ${ODOO_SRC}/odoo-bin -c ${ODOO_CONF}
StandardOutput=journal+console
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl start "${SERVICE_NAME}"
sleep 3

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    success "Odoo service started successfully"
else
    error "Odoo service failed to start. Check: journalctl -u ${SERVICE_NAME} -n 50"
fi

# ============================================================
#  STEP 11 — Nginx (optional)
# ============================================================
if [[ "${SETUP_NGINX,,}" == "y" ]]; then
    step "Configuring Nginx"
    apt-get install -y nginx

    cat > "/etc/nginx/sites-available/${ODOO_USER}" <<EOF
upstream ${ODOO_USER} {
    server 127.0.0.1:${ODOO_PORT};
}

server {
    listen 80;
    server_name ${DOMAIN_NAME};

    access_log /var/log/nginx/${ODOO_USER}.access.log;
    error_log  /var/log/nginx/${ODOO_USER}.error.log;

    proxy_read_timeout    720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout    720s;

    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    location / {
        proxy_pass http://${ODOO_USER};
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering   on;
        proxy_pass        http://${ODOO_USER};
    }

    gzip on;
    gzip_types text/css text/plain application/javascript application/json;
}
EOF

    ln -sf "/etc/nginx/sites-available/${ODOO_USER}" "/etc/nginx/sites-enabled/${ODOO_USER}"
    nginx -t && systemctl reload nginx
    success "Nginx configured for ${DOMAIN_NAME}"

    # SSL
    if [[ "${SETUP_SSL,,}" == "y" ]]; then
        step "Setting up SSL with Let's Encrypt"
        sudoapt-get install -y -qq certbot python3-certbot-nginx
        certbot --nginx -d "${DOMAIN_NAME}" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" || \
            warn "SSL setup failed — check DNS and try: certbot --nginx -d ${DOMAIN_NAME}"
        success "SSL certificate installed"
    fi
fi

# ============================================================
#  DONE
# ============================================================
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Odoo ${ODOO_VERSION} Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Access URL:${NC}"
if [[ "${SETUP_NGINX,,}" == "y" ]]; then
    echo -e "    https://${DOMAIN_NAME}"
else
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "    http://${SERVER_IP}:${ODOO_PORT}"
fi
echo ""
echo -e "  ${BOLD}Service management:${NC}"
echo -e "    sudo systemctl start|stop|restart ${SERVICE_NAME}"
echo -e "    sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo -e "  ${BOLD}Log file:${NC} ${ODOO_LOG}"
echo -e "  ${BOLD}Config:${NC}   ${ODOO_CONF}"
echo ""
echo -e "${YELLOW}  SECURITY: Disable the DB manager in production!${NC}"
echo -e "${YELLOW}  Set  list_db = False  in ${ODOO_CONF}${NC}"
echo ""
