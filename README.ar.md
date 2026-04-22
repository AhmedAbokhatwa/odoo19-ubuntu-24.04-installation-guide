<kbd align="left">
  <a href="README.md">Read in English 🇬🇧</a>
</kbd>

# 🚀 مثبّت Odoo 19 — Ubuntu 24.04 LTS

> تثبيت Odoo 19 جاهز للإنتاج في دقائق.
> **Python 3.11 · PostgreSQL · Nginx (اختياري) · SSL (اختياري)**

---

## ⚡ التثبيت السريع

```bash
chmod +x install-odoo19.sh
sudo bash install-odoo19.sh
```

السكربت سيطلب منك جميع القيم المطلوبة — لا حاجة لتعديل أي ملف.

---

## 📋 ما يقوم السكربت بضبطه

| المتغير | الافتراضي | الوصف |
|---|---|---|
| مستخدم النظام | `odoo19` | مستخدم OS مخصص لـ Odoo |
| مسار التثبيت | `/opt/odoo19` | المجلد الرئيسي |
| إصدار Odoo | `19.0` | الفرع المُستنسخ من git |
| منفذ HTTP | `8069` | المنفذ الذي يستمع عليه Odoo |
| كلمة مرور المدير | *(مطلوبة)* | كلمة مرور مدير قواعد البيانات |
| كلمة مرور DB | *(مطلوبة)* | كلمة مرور مستخدم PostgreSQL |
| Workers | `4` | عدد عمليات Odoo |
| Nginx | *(اختياري)* | إعداد الـ reverse proxy |
| Domain + SSL | *(اختياري)* | شهادة Let's Encrypt |

---

## 🛠️ التثبيت اليدوي

اتبع هذه الخطوات إذا كنت تفضل التثبيت اليدوي أو تريد فهم ما يقوم به السكربت.

### المتطلبات الأساسية

- Ubuntu 24.04 LTS (64-bit)
- صلاحيات root أو sudo
- ذاكرة RAM لا تقل عن 2 GB، مساحة قرص 20 GB

---

### الخطوة 1 — تحديث النظام وتثبيت المتطلبات

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

### الخطوة 2 — تثبيت Node.js 22 و rtlcss

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo npm install -g rtlcss
```

> `rtlcss` مطلوب لدعم واجهات RTL (العربية وغيرها).

---

### الخطوة 3 — تثبيت wkhtmltopdf (النسخة المُعدَّلة)

```bash
sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -y ./wkhtmltox_0.12.6.1-3.jammy_amd64.deb
```

> ⚠️ استخدم هذه النسخة المُعدَّلة تحديداً — حزمة Ubuntu الافتراضية لا تدعم الترويسات والتذييلات في تقارير PDF.

---

### الخطوة 4 — إعداد PostgreSQL

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql

# إنشاء مستخدم قاعدة البيانات (استبدل YOUR_PASSWORD بكلمة مرورك)
sudo -u postgres psql -c "CREATE USER odoo19 WITH CREATEDB NOSUPERUSER NOCREATEROLE PASSWORD 'YOUR_PASSWORD';"
```

---

### الخطوة 5 — إنشاء مستخدم النظام والمجلدات

```bash
sudo adduser --system --home /opt/odoo19 --group odoo19

sudo mkdir -p /opt/odoo19/odoo-custom-addons
sudo mkdir -p /var/log/odoo19

sudo chown -R odoo19:odoo19 /opt/odoo19 /var/log/odoo19
```

---

### الخطوة 6 — استنساخ Odoo 19

```bash
sudo -u odoo19 git clone https://github.com/odoo/odoo.git \
    --depth 1 --branch 19.0 /opt/odoo19/odoo
```

---

### الخطوة 7 — بيئة Python 3.11 الافتراضية

```bash
sudo -u odoo19 python3.11 -m venv /opt/odoo19/odoo-venv

# التحقق من إصدار Python داخل الـ venv
sudo -u odoo19 /opt/odoo19/odoo-venv/bin/python --version
# المتوقع: Python 3.11.x
```

> ❌ لا تستخدم Python 3.10 — Odoo 19 يثبت `Babel==2.9.1` لـ Python < 3.11 وهو غير متوافق مع monkeypatch الـ pytz الداخلي في Odoo 19.

---

### الخطوة 8 — تثبيت تبعيات Python

```bash
sudo -u odoo19 bash -c "
    source /opt/odoo19/odoo-venv/bin/activate && \
    pip install --upgrade pip setuptools wheel && \
    pip install -r /opt/odoo19/odoo/requirements.txt
"
```

> هذه الخطوة تُجمِّع gevent و lxml و psycopg2 من المصدر. تستغرق من 5 إلى 15 دقيقة.

---

### الخطوة 9 — ملف إعدادات Odoo

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

### الخطوة 10 — خدمة Systemd

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

# التحقق
sudo systemctl status odoo19
```

---

### الخطوة 11 — Nginx كـ Reverse Proxy (اختياري)

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

للـ SSL، أضف `proxy_mode = True` في `/etc/odoo19.conf`، ثم:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d erp.example.com
```

---

## 🔧 أوامر مفيدة

```bash
# إدارة الخدمة
sudo systemctl start|stop|restart|status odoo19

# متابعة اللوق مباشرة
sudo journalctl -u odoo19 -f

# ملف اللوق
sudo tail -f /var/log/odoo19/odoo19.log

# تحديث موديول معين
sudo -u odoo19 /opt/odoo19/odoo-venv/bin/python \
    /opt/odoo19/odoo/odoo-bin -c /etc/odoo19.conf \
    -u my_module -d my_database --stop-after-init

# تشغيل يدوي للاختبار (بدون systemd)
sudo -u odoo19 /opt/odoo19/odoo-venv/bin/python \
    /opt/odoo19/odoo/odoo-bin -c /etc/odoo19.conf
```

---

## 🔐 قائمة تدقيق الأمان

- [ ] غيّر كلمة مرور المدير فور أول تسجيل دخول
- [ ] اضبط `list_db = False` في الإعدادات للبيئة الإنتاجية
- [ ] لا تكشف المنفذ 8069 مباشرة — استخدم Nginx دائماً
- [ ] فعّل جدار الحماية: `sudo ufw allow 22,80,443/tcp && sudo ufw enable`
- [ ] جدوِل نسخاً احتياطية منتظمة: `pg_dump -U odoo19 mydb > backup.sql`

---

## 🐛 حل المشاكل الشائعة

| الخطأ | السبب | الحل |
|---|---|---|
| `Babel/pytz ImportError` | إصدار Python خاطئ | استخدم Python 3.11 وليس 3.10 |
| فشل بناء `psycopg2` | غياب `libpq-dev` | `sudo apt install libpq-dev` |
| فشل بناء `gevent` | pip/setuptools قديم | `pip install --upgrade pip setuptools wheel` |
| خطأ صلاحيات | ملكية ملفات خاطئة | `sudo chown -R odoo19:odoo19 /opt/odoo19` |
| المنفذ 8069 مرفوض | الخدمة لا تعمل | `sudo systemctl status odoo19` |
| خطأ الاتصال بـ DB | كلمة مرور خاطئة | راجع `db_password` في `/etc/odoo19.conf` |
| أخطاء GPG في apt | مستودعات طرف ثالث تالفة | `sudo rm -f /etc/apt/sources.list.d/*microsoft*` |

---

## 📁 هيكل الملفات

```
/opt/odoo19/
├── odoo/                  # كود Odoo المصدري (git)
├── odoo-venv/             # بيئة Python 3.11 الافتراضية
└── odoo-custom-addons/    # موديولاتك المخصصة

/etc/odoo19.conf           # ملف الإعدادات الرئيسي
/var/log/odoo19/           # ملفات اللوق
/etc/systemd/system/odoo19.service
```

---

## 📄 الرخصة

MIT — حر الاستخدام والتعديل والتوزيع.
