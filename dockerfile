FROM odoo:16.0

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl netcat-openbsd postgresql-client gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Archivos de arranque y plantilla
COPY start.sh /start.sh
COPY odoo.conf.tmpl /odoo.conf.tmpl
RUN chmod +x /start.sh \
 && mkdir -p /etc/odoo /var/log/odoo \
 && chown -R odoo:odoo /etc/odoo /var/log/odoo /var/lib/odoo

# Ejecutaremos como el usuario 'odoo' (ya existe en la imagen oficial)
USER odoo
ENV PYTHONUNBUFFERED=1

# Render ejecuta este CMD
CMD ["/start.sh"]
