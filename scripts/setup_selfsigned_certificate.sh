#!/bin/bash
#
# setup_selfsigned_certificate.sh
# Crea un certificado autofirmado con subjectAltName y configura Apache
# para servir el sitio por HTTPS, redirigiendo HTTP -> HTTPS.
# Todas las variables se leen de scripts/.env
#
# Uso: sudo ./scripts/setup_selfsigned_certificate.sh

set -euo pipefail

# Rutas del propio repositorio, calculadas a partir de la ubicación del script
# para que funcione se lance desde donde se lance
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
CONF_DIR="$SCRIPT_DIR/../conf"

# 0. Permisos de administrador
if [[ $EUID -ne 0 ]]; then
    echo "Error: ejecuta el script con sudo: sudo $0" >&2
    exit 1
fi

# 1. Comprobar que Apache está instalado
if ! dpkg -s apache2 2>/dev/null | grep -q "Status: install ok installed"; then
    echo "Error: Apache no está instalado. Ejecuta antes: sudo ./scripts/install_apache.sh" >&2
    exit 1
fi

# 2. Leer las variables del archivo .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: no existe $ENV_FILE. Créalo con: cp scripts/.env.example scripts/.env" >&2
    exit 1
fi

# set -a exporta automáticamente todas las variables que se definan al cargar el .env
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Comprobar que no falta ninguna variable
REQUIRED_VARS=(CERT_COUNTRY CERT_STATE CERT_LOCALITY CERT_ORGANIZATION CERT_ORG_UNIT
               CERT_EMAIL DOMAIN ELASTIC_IP CERT_DAYS CERT_KEY CERT_CRT APACHE_SITES_DIR)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: la variable $var no está definida en $ENV_FILE" >&2
        exit 1
    fi
done

# 3. Crear la clave privada y el certificado autofirmado con subjectAltName
echo "Creando el certificado autofirmado para $DOMAIN ($ELASTIC_IP)..."
mkdir -p "$(dirname "$CERT_KEY")" "$(dirname "$CERT_CRT")"

openssl req -x509 -nodes -days "$CERT_DAYS" -newkey rsa:2048 \
    -keyout "$CERT_KEY" \
    -out "$CERT_CRT" \
    -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORGANIZATION/OU=$CERT_ORG_UNIT/CN=$DOMAIN/emailAddress=$CERT_EMAIL" \
    -addext "subjectAltName=DNS:$DOMAIN,IP:$ELASTIC_IP"

# La clave privada solo la puede leer root; el certificado es público
chown root:root "$CERT_KEY" "$CERT_CRT"
chmod 600 "$CERT_KEY"
chmod 644 "$CERT_CRT"

# 4. Copiar las plantillas de conf/ y sustituir los marcadores con sed.
#    Se usa | como separador de sed porque las rutas contienen /
echo "Copiando los virtual hosts a $APACHE_SITES_DIR..."
for conf in 000-default.conf practica-https-ssl.conf; do
    cp "$CONF_DIR/$conf" "$APACHE_SITES_DIR/$conf"
    sed -i \
        -e "s|__DOMAIN__|$DOMAIN|g" \
        -e "s|__CERT_CRT__|$CERT_CRT|g" \
        -e "s|__CERT_KEY__|$CERT_KEY|g" \
        "$APACHE_SITES_DIR/$conf"
done

# 5. Habilitar los módulos ssl y rewrite y los sitios
a2enmod ssl rewrite
a2ensite 000-default.conf practica-https-ssl.conf

# 6. Comprobar la configuración antes de reiniciar; si falla, no se reinicia
echo "Comprobando la configuración de Apache..."
if ! apache2ctl configtest; then
    echo "Error: la configuración de Apache no es válida. No se reinicia el servicio." >&2
    exit 1
fi

systemctl restart apache2

echo "HTTPS configurado. Prueba: curl -kI https://$DOMAIN"
