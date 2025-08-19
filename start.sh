#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
export CATALINA_HOME="/usr/local/tomcat"
export CATALINA_BASE="/usr/local/tomcat"
export OB_DB_PASSWORD="${OB_DB_PASSWORD:-openboxes}"
export MYSQL_SOCK="/run/mysqld/mysqld.sock"

echo "[start] PORT=$PORT"

# --- MariaDB: preparar socket y datos ---
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "[start] Inicializando MariaDB..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi

# --- MariaDB: arrancar (log a /tmp para evitar permisos) ---
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

# --- Esperar MariaDB por socket ---
for i in {1..60}; do
  if mysqladmin --socket="${MYSQL_SOCK}" -uroot ping --silent; then
    break
  fi
  sleep 2
done

# --- Bootstrap DB/usuario (por socket) ---
echo "[start] Creando DB/usuario si faltan..."
mysql --socket="${MYSQL_SOCK}" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS openboxes DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'openboxes'@'localhost' IDENTIFIED BY '${OB_DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'openboxes'@'127.0.0.1' IDENTIFIED BY '${OB_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'localhost';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

# --- Tomcat: forzar a 8080 (interno) ---
cat > "${CATALINA_HOME}/conf/server.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector address="0.0.0.0" port="8080" protocol="HTTP/1.1"
               connectionTimeout="20000" redirectPort="8443" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
    </Engine>
  </Service>
</Server>
EOF

# --- Abrir YA el puerto que Render espera con un proxy a 8080 ---
# --- Tomcat: forzar a 8080 (interno) ---
cat > "${CATALINA_HOME}/conf/server.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector address="0.0.0.0" port="8080" protocol="HTTP/1.1"
               connectionTimeout="20000" redirectPort="8443" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
    </Engine>
  </Service>
</Server>
EOF

# --- Placeholder HTTP inmediato en $PORT ---
# Responde "200 OK" con texto mientras arranca Tomcat
socat TCP-LISTEN:${PORT},fork,reuseaddr SYSTEM:'printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-cache\r\n\r\nOpenBoxes se está iniciando...\n";' &
PLACEHOLDER_PID=$!
echo "[start] placeholder HTTP PID=${PLACEHOLDER_PID} escuchando en 0.0.0.0:${PORT}"

# --- Arrancar Tomcat en 8080 ---
export CATALINA_OPTS="${CATALINA_OPTS:-} -Xms256m -Xmx384m -XX:+UseG1GC -Djava.awt.headless=true"
echo "[start] Arrancando Tomcat en 8080 ..."
/usr/local/tomcat/bin/catalina.sh start

# --- Esperar a que Tomcat realmente responda HTTP en 8080 ---
echo "[start] Esperando a que Tomcat responda en http://127.0.0.1:8080/ ..."
for i in {1..120}; do
  if curl -sSf -o /dev/null http://127.0.0.1:8080/; then
    READY=1
    break
  fi
  sleep 2
done
if [ "${READY:-0}" -ne 1 ]; then
  echo "[start] Tomcat no respondió a tiempo, mostrando placeholder indefinidamente."
  # Mantener el proceso en foreground para que el contenedor no termine
  tail -f /dev/null
fi

# --- Tomcat ya está sirviendo: cambiar de placeholder a proxy ---
echo "[start] Tomcat responde. Cambiando de placeholder a proxy..."
kill ${PLACEHOLDER_PID} || true
# pequeño delay para liberar el puerto
sleep 0.5
socat TCP-LISTEN:${PORT},fork,reuseaddr TCP:127.0.0.1:8080 &
PROXY_PID=$!
echo "[start] proxy socat PID=${PROXY_PID} (0.0.0.0:${PORT} -> 127.0.0.1:8080)"

# --- Poner Tomcat en foreground para que Render vea el proceso principal ---
exec /usr/local/tomcat/bin/catalina.sh run


echo "[start] Arrancando Tomcat en 8080 ..."
exec /usr/local/tomcat/bin/catalina.sh run
