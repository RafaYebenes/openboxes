#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
export CATALINA_HOME="/usr/local/tomcat"
export CATALINA_BASE="/usr/local/tomcat"
export OB_DB_PASSWORD="${OB_DB_PASSWORD:-openboxes}"
export MYSQL_SOCK="/run/mysqld/mysqld.sock"

echo "[start] PORT=$PORT"

# --- MariaDB socket & data ---
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld
if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "[start] Inicializando MariaDB..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi

echo "[start] Lanzando mysqld..."
mysqld \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --socket="${MYSQL_SOCK}" \
  --bind-address=127.0.0.1 \
  --skip-name-resolve \
  --skip-host-cache \
  --log-error=/tmp/mysql.err &

# Esperar a MariaDB
for i in {1..60}; do
  if mysqladmin --socket="${MYSQL_SOCK}" -uroot ping --silent; then break; fi
  sleep 2
done

echo "[start] Creando DB/usuario si faltan..."
mysql --socket="${MYSQL_SOCK}" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS openboxes DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'openboxes'@'localhost' IDENTIFIED BY '${OB_DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'openboxes'@'127.0.0.1' IDENTIFIED BY '${OB_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'localhost';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

# --- Tomcat escuchando DIRECTAMENTE en $PORT ---
cat > "${CATALINA_HOME}/conf/server.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector address="0.0.0.0" port="${PORT}" protocol="HTTP/1.1"
               connectionTimeout="20000" redirectPort="8443" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
    </Engine>
  </Service>
</Server>
EOF

# Página mínima para que Render vea 200 OK inmediato
mkdir -p /usr/local/tomcat/webapps/ROOT
printf 'OK\n' > /usr/local/tomcat/webapps/ROOT/index.html

# Memoria moderada (ajusta si hace falta)
export CATALINA_OPTS="-Xms256m -Xmx768m -XX:+UseG1GC -Djava.awt.headless=true"

echo "[start] Arrancando Tomcat en ${PORT} ..."
# IMPORTANTE: un único proceso en foreground, sin socat, sin curl, sin 'start'
exec /usr/local/tomcat/bin/catalina.sh run
