#!/bin/bash
#
# install_apache.sh
# Instala Apache en Ubuntu sin intervención del usuario.
# Si Apache ya está instalado, termina sin hacer nada.
#
# Uso: sudo ./scripts/install_apache.sh

# -e: sale si un comando falla | -u: error si se usa una variable sin definir
# -o pipefail: una tubería falla si falla cualquiera de sus comandos
set -euo pipefail

# 1. El script necesita permisos de administrador
if [[ $EUID -ne 0 ]]; then
    echo "Error: ejecuta el script con sudo: sudo $0" >&2
    exit 1
fi

# 2. Comprobar con dpkg -s si Apache ya está instalado.
#    Se busca "install ok installed" porque un paquete desinstalado sin purgar
#    (estado "deinstall ok config-files") también hace que dpkg -s devuelva 0.
if dpkg -s apache2 2>/dev/null | grep -q "Status: install ok installed"; then
    echo "Apache ya está instalado."
    exit 0
fi

# 3. Instalar Apache sin preguntas
#    DEBIAN_FRONTEND=noninteractive: apt no muestra diálogos de configuración
#    NEEDRESTART_MODE=a: needrestart reinicia servicios sin preguntar
#    DPkg::Lock::Timeout=300: espera hasta 5 min si otro proceso (p. ej.
#    unattended-upgrades en una instancia recién creada) tiene bloqueado apt
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "Actualizando la lista de paquetes..."
apt-get -o DPkg::Lock::Timeout=300 update -y

echo "Instalando Apache..."
apt-get -o DPkg::Lock::Timeout=300 install -y apache2

# 4. Dejar el servicio habilitado (arranca con el sistema) y en marcha
systemctl enable --now apache2

echo "Apache instalado correctamente."
systemctl is-active apache2
systemctl is-enabled apache2
