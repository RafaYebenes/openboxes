#!/usr/bin/env bash
set -e

# Render expone el puerto en $PORT; si no está, usa 10000
export PORT="${PORT:-10000}"
export CATALINA_HOME=/usr/local/tomcat
export OB_DB_PASSWORD="${OB_DB_PASSWORD:-openboxes}"

# Inicia/Inicializa MariaDB (solo para demo, sin disco persistente)
if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "Inicializando MariaDB..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi

# Arranca MariaDB escuchando solo en loopback
mysqld --user=mysql --bind-address=127.0.0.1 --skip-name-resolve --skip-networking=0 &
# Espera a que arranque
for i in {1..60}; do
  mysqladmin ping --silent && break
  sleep 2
done

# Crea DB y usuario si no existen
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS openboxes DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'openboxes'@'localhost' IDENTIFIED BY '${OB_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON openboxes.* TO 'openboxes'@'localhost';
FLUSH PRIVILEGES;
SQL

# Ajusta Tomcat para escuchar en $PORT (requisito de Render)
sed -i "s/port=\"8080\" protocol=\"HTTP\/1.1\"/port=\"${PORT}\" protocol=\"HTTP\/1.1\"/" "$CATALINA_HOME/conf/server.xml"

# Limita memoria (plan Free ~512MB): baja Xmx para evitar OOM
export CATALINA_OPTS="${CATALINA_OPTS} -Xms256m -Xmx384m -XX:+UseG1GC"

# Lanza Tomcat (desplegará openboxes.war)
exec catalina.sh run
