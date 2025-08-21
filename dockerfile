# Odoo 16 (LTS)
FROM odoo:16.0

# Paquetes útiles (y cliente PG por si necesitas debug desde el contenedor)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl netcat-telnet postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# (opcional) Asegurar versión de psycopg2
RUN pip install --no-cache-dir psycopg2-binary==2.9.9

# Copiamos arranque y plantilla de config
COPY start.sh /start.sh
COPY odoo.conf.tmpl /odoo.conf.tmpl
RUN chmod +x /start.sh

# Odoo lee por defecto /etc/odoo/odoo.conf
ENV ODOO_RC=/etc/odoo/odoo.conf

EXPOSE 8069
CMD ["/start.sh"]
