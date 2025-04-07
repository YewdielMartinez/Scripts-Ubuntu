#!/bin/bash
source ./utils.sh

function configurar_ssh() {
    # Instalar el servidor SSH
    sudo apt update
    sudo apt install -y openssh-server

    # Habilitar y arrancar el servicio SSH
    sudo systemctl enable ssh
    sudo systemctl start ssh

    # Configurar el archivo sshd_config con valores por defecto
    puerto=$(solicitar_input "Introduce el puerto para SSH (default 22): ")
    puerto=${puerto:-22}

    permitir_root=$(solicitar_input "¿Permitir acceso root? (yes/no, default no): ")
    permitir_root=${permitir_root:-no}

    autenticacion_clave=$(solicitar_input "¿Permitir autenticación por contraseña? (yes/no, default yes): ")
    autenticacion_clave=${autenticacion_clave:-yes}

    # Modificar configuración según las entradas del usuario
    sudo sed -i "s/^#Port 22/Port $puerto/" /etc/ssh/sshd_config
    sudo sed -i "s/^#PermitRootLogin.*/PermitRootLogin $permitir_root/" /etc/ssh/sshd_config
    sudo sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication $autenticacion_clave/" /etc/ssh/sshd_config

    # Reiniciar el servicio para aplicar cambios
    sudo systemctl restart ssh

    PrintMessage "Configuración completada. El servidor SSH está instalado y configurado." "info"
}  # <---- ESTA LLAVE FALTABA
configurar_ssh