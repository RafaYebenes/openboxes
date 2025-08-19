#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
export CATALINA_HOME=/usr/local/tomcat
export OB_DB_PASSWORD="${OB_DB_PASSWORD:-openboxes}"

# --- Asegurar rutas de runtime para MariaDB ---
# /run/mysqld es donde vive el socket por defecto en Debian/Ubuntu
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

# --- Inicializar datos si hace falta ---
if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "Inicializando MariaDB..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi

# --- Arrancar MariaDB ---
# Forzamos socket y bind explícitos
mysqld \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --socket=/run/mysqld/mysqld.sock \
  --bind-address=127.0.0.1 \
  --skip-name-resolve \
  --skip-host-cache \
  --log-error=/var/log/mysql.err \
  &

# --- Esperar a que MariaDB esté listo (vía TCP para evitar sockets) ---
for i in {1..60}; do
  if mysqladmin --protocol=TCP -h 127.0.0.1 -uroot ping --silent; then
    break
  fi
  sleep 2
done

# --- Crear DB/usuario si no existen (vía TCP) ---
mysql --protocol=TCP -h 127.0.0.1 -uroot <<SQL
CREATE DATABASE IF NOT EXISTS openboxes DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'openboxes'@'localhost' IDENTIFIED BY '${OB_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- Ajustar Tomcat al puerto que exige Render ---
# (Tomcat ya escucha en 0.0.0.0 por defecto; solo cambiamos el puerto)
sed -i "s/port=\"8080\" protocol=\"HTTP\/1.1\"/port=\"${PORT}\" protocol=\"HTTP\/1.1\"/" "$CATALINA_HOME/conf/server.xml"

# --- Limitar memoria para plan Free (~512MB) ---
export CATALINA_OPTS="${CATALINA_OPTS:-} -Xms256m -Xmx384m -XX:+UseG1GC"

# --- Lanzar Tomcat (desplegará openboxes.war) ---
exec catalina.sh run
