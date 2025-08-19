#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
export CATALINA_HOME=/usr/local/tomcat
export OB_DB_PASSWORD="${OB_DB_PASSWORD:-openboxes}"
export MYSQL_SOCK="/run/mysqld/mysqld.sock"

# --- Preparar socket y datos ---
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "Inicializando MariaDB..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi

# --- Arrancar MariaDB (log en /tmp para evitar permisos) ---
mysqld \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --socket="${MYSQL_SOCK}" \
  --bind-address=127.0.0.1 \
  --skip-name-resolve \
  --skip-host-cache \
  --log-error=/tmp/mysql.err \
  &

# --- Esperar a que esté listo (por socket, no TCP) ---
for i in {1..60}; do
  if mysqladmin --socket="${MYSQL_SOCK}" -uroot ping --silent; then
    break
  fi
  sleep 2
done

# --- Bootstrap DB/usuario (por socket) ---
mysql --socket="${MYSQL_SOCK}" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS openboxes DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'openboxes'@'localhost' IDENTIFIED BY '${OB_DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'openboxes'@'127.0.0.1' IDENTIFIED BY '${OB_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'localhost';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

# --- Ajustar Tomcat al puerto de Render ---
sed -i "s/port=\"8080\" protocol=\"HTTP\/1.1\"/port=\"${PORT}\" protocol=\"HTTP\/1.1\"/" "$CATALINA_HOME/conf/server.xml"

# --- Limitar memoria para plan Free ---
export CATALINA_OPTS="${CATALINA_OPTS:-} -Xms256m -Xmx384m -XX:+UseG1GC"

# --- Lanzar Tomcat en foreground ---
exec catalina.sh run
