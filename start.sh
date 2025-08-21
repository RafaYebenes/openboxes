#!/usr/bin/env bash
set -euo pipefail

# Requisitos de DB desde Neon (Render -> Environment):
# PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
: "${PGHOST:?Define PGHOST}"
: "${PGPORT:=5432}"
: "${PGUSER:?Define PGUSER}"
: "${PGPASSWORD:?Define PGPASSWORD}"
: "${PGDATABASE:?Define PGDATABASE}"

# Parámetros Odoo (puedes sobreescribirlos desde Render)
: "${ODOO_ADMIN_PASSWORD:=admin}"
: "${ODOO_DB_FILTER:=.*}"
: "${ODOO_WORKERS:=0}"        # 0 = modo single-thread (ok para plan free)
: "${ODOO_LIMIT_MEMORY_SOFT:=268435456}"   # 256MB
: "${ODOO_LIMIT_MEMORY_HARD:=402653184}"   # 384MB
: "${ODOO_LIMIT_TIME_CPU:=60}"
: "${ODOO_LIMIT_TIME_REAL:=120}"
: "${ODOO_LOG_LEVEL:=info}"

mkdir -p /etc/odoo /var/lib/odoo /var/log/odoo
chown -R odoo:odoo /var/lib/odoo /var/log/odoo

# Render está detrás de proxy
export ODOO_PROXY_MODE=${ODOO_PROXY_MODE:-True}

# Generar config a partir de plantilla
cat /odoo.conf.tmpl | envsubst > /etc/odoo/odoo.conf
echo "[start] Config escrita en /etc/odoo/odoo.conf:"
sed -e 's/password=.*/password=***REDACTED***/' /etc/odoo/odoo.conf | sed -e 's/admin_passwd=.*/admin_passwd=***REDACTED***/' | tee /dev/stderr >/dev/null

# Esperar a DB (Neon requiere SSL)
echo "[start] Probando conexión a Postgres (${PGHOST}:${PGPORT}) ..."
until PGPASSWORD="$PGPASSWORD" psql \
    "host=${PGHOST} port=${PGPORT} user=${PGUSER} dbname=${PGDATABASE} sslmode=require" \
    -c "select 1;" >/dev/null 2>&1; do
  echo "[start] DB no responde todavía, reintento en 2s..."
  sleep 2
done

# Lanzar odoo
echo "[start] Arrancando Odoo en :8069 ..."
exec gosu odoo odoo -c /etc/odoo/odoo.conf
