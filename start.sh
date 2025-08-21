#!/usr/bin/env bash
set -euo pipefail

# -------- Variables requeridas --------
: "${PGHOST:?Falta PGHOST}"
: "${PGPORT:=5432}"
: "${PGDATABASE:?Falta PGDATABASE}"
: "${PGUSER:?Falta PGUSER}"
: "${PGPASSWORD:?Falta PGPASSWORD}"
: "${PORT:=8069}"
: "${ADMIN_PASSWD:=admin}"

export PGPASSWORD="$PGPASSWORD"

# -------- Generar odoo.conf desde la plantilla --------
envsubst < /odoo.conf.tmpl > /tmp/odoo.conf
mv /tmp/odoo.conf /etc/odoo/odoo.conf

echo "[start] Config escrita en /etc/odoo/odoo.conf:"
cat /etc/odoo/odoo.conf

# -------- Esperar a Postgres --------
echo "[start] Probando conexión a Postgres (${PGHOST}:${PGPORT}) ..."
for i in {1..60}; do
  if nc -z "${PGHOST}" "${PGPORT}"; then
    echo "[start] Postgres accesible."
    break
  fi
  sleep 2
done

# -------- Arrancar Odoo en $PORT --------
echo "[start] Arrancando Odoo en :${PORT} ..."
exec odoo -c /etc/odoo/odoo.conf
