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
