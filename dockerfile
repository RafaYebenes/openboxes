# Tomcat con Java 11 (compatible con OpenBoxes 0.9.x)
FROM tomcat:9.0-jdk11-temurin

# Instala MariaDB (drop-in de MySQL) y curl
RUN apt-get update && apt-get install -y mariadb-server curl && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/mysqld && chown -R mysql:mysql /run/mysqld

# Descarga el WAR más reciente de OpenBoxes desde GitHub Releases
# (Render descargará el asset en cada build)
RUN curl -s https://api.github.com/repos/openboxes/openboxes/releases/latest \
 | grep browser_download_url | grep openboxes.war | cut -d '"' -f 4 \
 | xargs curl -L -o /usr/local/tomcat/webapps/openboxes.war

 # Página mínima para que "/" responda 200 OK desde el segundo 0
RUN mkdir -p /usr/local/tomcat/webapps/ROOT \
&& printf 'OpenBoxes se está iniciando...\n' > /usr/local/tomcat/webapps/ROOT/index.html

# Config por defecto en la ruta que Tomcat lee (~/.grails)
RUN mkdir -p /usr/local/tomcat/.grails
COPY openboxes-config.properties /usr/local/tomcat/.grails/openboxes-config.properties

# Script de arranque: levanta MariaDB y luego Tomcat en el puerto $PORT de Render
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 10000

EXPOSE 8080
CMD ["/start.sh"]
