#!/bin/bash

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

# Función para configurar el servidor DNS
function configurar_dns() {
    # Solicitar parámetros al usuario
    dominio=$(solicitar_input "Introduce el nombre de dominio: ")
    ip_servidor=$(solicitar_input "Introduce la direccion IP asociada al dominio: ")

    # Actualizar el sistema e instalar Bind9
    sudo apt install bind9 bind9-utils -y

    # Configurar named.conf.options
    sudo tee /etc/bind/named.conf.options > /dev/null <<EOL
options {
    directory "/var/cache/bind";
    listen-on { any; };
    allow-query { localhost; $(echo "$ip_servidor" | cut -d'.' -f1-3).0/24; };
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    dnssec-validation no;
    auth-nxdomain no;    # conform to RFC1035
    listen-on-v6 { none; };
};
EOL

    # Configurar uso de solo IPv4
    sudo sed -i 's/^OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named

    # Crear directorio para las zonas si no existe
    sudo mkdir -p /etc/bind/zonas

    # Configurar named.conf.local
    sudo tee /etc/bind/named.conf.local > /dev/null <<EOL
zone "$dominio" IN {
    type master;
    file "/etc/bind/zonas/db.$dominio";
};
EOL

    # Crear archivo de zona directa
    sudo tee /etc/bind/zonas/db.$dominio > /dev/null <<EOL
;
; BIND data file for $dominio
;
\$TTL    604800
@       IN      SOA     geralchoki. admin.$dominio. (
                             2         ; Serial
                        604800         ; Refresh
                         86400         ; Retry
                       2419200         ; Expire
                        604800 )       ; Negative Cache TTL
;
@       IN      NS      geralchoki.
ns1     IN      A       $ip_servidor
www     IN      A       $ip_servidor
@       IN      A       $ip_servidor
EOL

    # Verificar configuración de Bind9
    sudo named-checkconf
    if [ $? -ne 0 ]; then
        echo "Error en la configuracion de Bind9. Por favor, revisa los archivos de configuracion."
        exit 1
    fi

    # Reiniciar servicio Bind9
    sudo systemctl restart bind9
    sudo systemctl enable bind9

    # Modificar /etc/resolv.conf
    sudo tee /etc/resolv.conf > /dev/null <<EOL
nameserver $ip_servidor
EOL

    echo "Configuracion completada. El servidor DNS esta instalado y configurado."
}

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

# Funcion para validar una direccion IP
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}


# Funcion para configurar una IP fija en Ubuntu Server 24.04
set_static_ip() {
    read -p "Desea configurar una IP fija? (S/N): " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return
    
    read -p "Ingrese la interfaz de red (ejemplo: eth0): " interface
    read -p "Ingrese la nueva IP del servidor (ejemplo: 192.168.0.10/24): " ip_address

    # Validar IP
    if ! validate_ip "$ip_address"; then
        echo "⚠️ Error: La dirección IP ingresada no es válida."
        return
    fi

    read -p "Ingrese la puerta de enlace (ejemplo: 192.168.0.1): " gateway
    read -p "Ingrese la dirección DNS primaria (ejemplo: 8.8.8.8): " dns1
    read -p "Ingrese la dirección DNS secundaria (opcional, presione Enter para omitir): " dns2

    # Verificar si se ingresó un segundo DNS
    if [[ -z "$dns2" ]]; then
        dns_config="addresses: [$dns1]"
    else
        dns_config="addresses: [$dns1, $dns2]"
    fi

    netplan_config="/etc/netplan/00-installer-config.yaml"
    sudo cp $netplan_config ${netplan_config}.bak

    echo "Configurando IP fija en la interfaz $interface..."
    
    sudo tee $netplan_config > /dev/null <<EOF
network:
  version: 2
  ethernets:
    $interface:
      dhcp4: no
      addresses:
        - $ip_address
      routes:
        - to: default
          via: $gateway
      nameservers:
        $dns_config
EOF

    # Ajustar permisos correctos para Netplan
    sudo chmod 600 /etc/netplan/00-installer-config.yaml

    # Aplicar configuración y verificar errores
    echo "Aplicando configuración..."
    if sudo netplan apply; then
        echo "✅ IP configurada correctamente en $interface con dirección $ip_address"
    else
        echo "❌ Error al aplicar la configuración. Restaurando respaldo..."
        sudo cp ${netplan_config}.bak $netplan_config
        sudo netplan apply
    fi
}

# Función para configurar SSH
function configurar_ssh() {
    echo "Instalando y configurando servidor SSH..."

    # Instalar OpenSSH Server
    sudo apt update && sudo apt install -y openssh-server

    # Verificar instalación
    if ! systemctl list-units --type=service | grep -q "ssh.service"; then
        echo "❌ Error: OpenSSH no se instaló correctamente."
        exit 1
    fi

    # Habilitar y arrancar SSH
    sudo systemctl enable ssh
    sudo systemctl start ssh

    # Configurar SSH
    read -rp "Introduce el puerto para SSH (default 22): " ssh_port
    ssh_port=${ssh_port:-22}

    read -rp "¿Deseas deshabilitar el acceso root por SSH? (S/N): " disable_root
    if [[ "$disable_root" =~ ^[Ss]$ ]]; then
        root_option="PermitRootLogin no"
    else
        root_option="PermitRootLogin yes"
    fi

    read -rp "¿Deseas habilitar la autenticación con clave pública únicamente? (S/N): " disable_password
    if [[ "$disable_password" =~ ^[Ss]$ ]]; then
        password_option="PasswordAuthentication no"
    else
        password_option="PasswordAuthentication yes"
    fi

    # Aplicar configuración en sshd_config
    sudo sed -i "/^Port /d" /etc/ssh/sshd_config
    sudo sed -i "/^PermitRootLogin /d" /etc/ssh/sshd_config
    sudo sed -i "/^PasswordAuthentication /d" /etc/ssh/sshd_config

    echo -e "\n# Configuración personalizada\nPort $ssh_port\n$root_option\n$password_option" | sudo tee -a /etc/ssh/sshd_config > /dev/null

    # Reiniciar servicio SSH
    sudo systemctl restart ssh

    echo "✅ Configuración de SSH completada."
    echo "Puedes conectar con: ssh usuario@IP -p $ssh_port"
}

while true; do
    echo "----------------------------"
    echo "Menú de Configuración"
    echo "1. Configurar servidor DNS"
    echo "2. Configurar servidor DHCP"
    echo "3. Configurar IP fija"
    echo "4. Configurar servidor SSH"
    echo "5. Salir"
    echo "----------------------------"
    read -rp "Opción: " opcion

    case $opcion in
        1) configurar_dns ;;
        2) configurar_dhcp ;;
        3) set_static_ip ;;
        4) configurar_ssh ;;
        5) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida. Inténtalo de nuevo." ;;
    esac
done