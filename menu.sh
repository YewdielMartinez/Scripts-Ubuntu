#!/bin/bash

# Incluir los otros scripts
source ./dns.sh
source ./dhcp.sh
source ./ssh.sh
source ./ip.sh
source ./ftp.sh
source ./http.sh

while true; do
    echo "----------------------------"
    echo "Menú de Configuración"
    echo "1. Configurar servidor DNS"
    echo "2. Configurar servidor DHCP"
    echo "3. Configurar IP fija"
    echo "4. Configurar servidor SSH"
    echo "5. Configurar servidor FTP"
    echo "6. Configurar servidor HTTP"
    echo "7. Salir"
    echo "----------------------------"
    read -rp "Opción: " opcion

    case $opcion in
        1) configurar_dns ;;
        2) configurar_dhcp ;;
        3) set_static_ip ;;
        4) configurar_ssh ;;
        4) configurar_ssh ;;
        5) configurar_ftp ;;
        6) main_menuhttp ;;
        7) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida. Inténtalo de nuevo." ;;
    esac
done
