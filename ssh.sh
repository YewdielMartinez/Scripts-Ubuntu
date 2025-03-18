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
