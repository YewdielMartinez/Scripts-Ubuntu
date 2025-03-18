#!/bin/bash
# Función para configurar el servidor DHCP
function configurar_dhcp() {
    # Solicitar parámetros al usuario para DHCP
    interfaz_v4=$(solicitar_input "Introduce la interfaz de red interna (ej. enp0s3): ")
    red=$(solicitar_input "Introduce la red (ej. 192.168.1.0): ")
    subred=$(solicitar_input "Introduce la submáscara (ej. 255.255.255.0): ")
    ip_inicio=$(solicitar_input "Introduce la IP donde empieza el rango (ej. 192.168.1.10): ")
    ip_fin=$(solicitar_input "Introduce la IP donde termina el rango (ej. 192.168.1.50): ")
    puerta_enlace=$(solicitar_input "Introduce la puerta de enlace (router) (ej. 192.168.1.1): ")
    dns=$(solicitar_input "Introduce el servidor DNS (ej. 8.8.8.8): ")

    # Instalar ISC DHCP Server
    sudo apt install isc-dhcp-server -y

    # Configurar la interfaz en /etc/default/isc-dhcp-server
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$interfaz_v4\"/" /etc/default/isc-dhcp-server

    # Configurar el archivo /etc/dhcp/dhcpd.conf
    sudo sed -i '/authoritative/d' /etc/dhcp/dhcpd.conf
    #sudo sed -i '/subnet/d' /etc/dhcp/dhcpd.conf
	sudo sed -i 's/^\(option domain-name \)/# \1/' /etc/dhcp/dhcpd.conf
    sudo sed -i 's/^\(option domain-name-servers \)/# \1/' /etc/dhcp/dhcpd.conf
    sudo tee -a /etc/dhcp/dhcpd.conf > /dev/null <<EOL

#authoritative;

subnet $red netmask $subred {
    range $ip_inicio $ip_fin;
    option routers $puerta_enlace;
    option domain-name-servers $dns;
}
EOL

    # Reiniciar servicio DHCP
    sudo systemctl start isc-dhcp-server
    sudo systemctl enable isc-dhcp-server

    echo "Configuracion completada. El servidor DHCP esta instalado y configurado."
}


# Función para solicitar entrada del usuario con validación
function solicitar_input() {
    local mensaje=$1
    local variable
    while true; do
        read -rp "$mensaje" variable
        if [[ -n $variable || -z $variable ]]; then
            echo "$variable"
            break
        else
            echo "Entrada no valida. Por favor, intentalo de nuevo."
        fi
    done
}