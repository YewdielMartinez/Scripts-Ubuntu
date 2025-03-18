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