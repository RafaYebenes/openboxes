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
  --log-error=/tmp/mysql.err \
  &

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

# --- Tomcat en 8080 ---
cat > "${CATALINA_HOME}/conf/server.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector address="0.0.0.0" port="8080"
               protocol="org.apache.coyote.http11.Http11NioProtocol"
               connectionTimeout="20000" redirectPort="8443" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
    </Engine>
  </Service>
</Server>
EOF

# --- Placeholder HTTP 200 inmediato en $PORT ---
BODY="OpenBoxes se está iniciando...\n"
# Construimos una respuesta HTTP válida con CRLF
printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s' "${#BODY}" "$BODY" \
  > /tmp/placeholder.http

# Servir la respuesta estática en $PORT (sin comillas problemáticas)
socat TCP-LISTEN:${PORT},fork,reuseaddr OPEN:/tmp/placeholder.http,rdonly &
PLACEHOLDER_PID=$!
echo "[start] placeholder PID=${PLACEHOLDER_PID} en 0.0.0.0:${PORT}"

# --- Arrancar Tomcat en foreground ---
export CATALINA_OPTS="${CATALINA_OPTS:-} -Xms512m -Xmx768m -XX:+UseG1GC -Djava.awt.headless=true -Djava.net.preferIPv4Stack=true"
echo "[start] Arrancando Tomcat en 8080 ..."
/usr/local/tomcat/bin/catalina.sh start

# Esperar a que Tomcat responda en 8080
echo "[start] Esperando a Tomcat (http://127.0.0.1:8080/)..."
READY=0
for i in {1..180}; do
  if curl -sSf -o /dev/null http://127.0.0.1:8080/; then READY=1; break; fi
  sleep 2
done

if [ "$READY" -ne 1 ]; then
  echo "[start] Tomcat no respondió a tiempo. Dejando placeholder indefinido."
  # Mantener proceso principal vivo
  exec tail -f /dev/null
fi

# Tomcat listo: cambiar de placeholder a proxy
echo "[start] Tomcat responde. Cambiando a proxy en ${PORT}..."
kill "${PLACEHOLDER_PID}" || true
sleep 0.5
socat TCP-LISTEN:${PORT},fork,reuseaddr TCP:127.0.0.1:8080 &
PROXY_PID=$!
echo "[start] proxy socat PID=${PROXY_PID} (0.0.0.0:${PORT} -> 127.0.0.1:8080)"

# Poner Tomcat en foreground (proceso principal)
exec /usr/local/tomcat/bin/catalina.sh run
