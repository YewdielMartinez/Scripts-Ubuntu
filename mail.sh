#!/bin/bash
source ./dns.sh

# Función para validar el nombre del usuario
validar_usuario() {
    local usuario="$1"
    if [[ ! "$usuario" =~ ^[a-z_][a-z0-9_-]{2,15}$ ]]; then
        echo "[ERROR] Nombre de usuario inválido. Debe tener entre 3 y 16 caracteres y solo puede contener letras minúsculas, números, guiones y guiones bajos."
        return 1
    fi
    return 0
}

# Función para validar la contraseña
validar_password() {
    local password="$1"
    if [[ ${#password} -lt 8 || ! "$password" =~ [A-Z] || ! "$password" =~ [a-z] || ! "$password" =~ [0-9] ]]; then
        echo "[ERROR] La contraseña debe tener al menos 8 caracteres, incluir una letra mayúscula, una minúscula y un número."
        return 1
    fi
    return 0
}

# Función para agregar un usuario de correo
agregar_usuario() {
    while true; do
        read -p "Ingrese el nombre del usuario: " usuario
        validar_usuario "$usuario" && break
    done

    while true; do
        read -s -p "Ingrese la contraseña del usuario: " password
        echo ""
        validar_password "$password" && break
    done

    sudo adduser --disabled-password --gecos "" "$usuario"
    echo "$usuario:$password" | sudo chpasswd

    # Verificar y crear la carpeta del usuario si no existe
    if [ ! -d "/home/$usuario" ]; then
        echo "[!] Carpeta /home/$usuario no existe. Creando manualmente..."
        sudo mkdir -p "/home/$usuario"
        sudo chown "$usuario:$usuario" "/home/$usuario"
        sudo chmod 755 "/home/$usuario"
    fi

    # Crear Maildir
    sudo mkdir -p "/home/$usuario/Maildir"
    sudo chown -R "$usuario:$usuario" "/home/$usuario/Maildir"
    sudo chmod -R 700 "/home/$usuario/Maildir"

    echo "[+] Usuario $usuario@$domain_name agregado correctamente."
}


# Función para eliminar un usuario de correo
eliminar_usuario() {
    read -p "Ingrese el nombre del usuario a eliminar: " usuario
    if id "$usuario" &>/dev/null; then
        sudo deluser --remove-home "$usuario"
        echo "[+] Usuario $usuario@$domain_name eliminado correctamente."
    else
        echo "[ERROR] El usuario no existe."
    fi
}

# Función para listar los usuarios de correo
listar_usuarios() {
    echo "[+] Usuarios de correo en el sistema:"
    awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd
}

# Función para verificar si un usuario existe
verificar_usuario() {
    read -p "Ingrese el nombre del usuario a verificar: " usuario
    if id "$usuario" &>/dev/null; then
        echo "[+] El usuario $usuario@$domain_name existe."
    else
        echo "[ERROR] El usuario no existe."
    fi
}

# Función para agregar nuevo dominio y configurarlo con Postfix, Dovecot y RainLoop
agregar_dominio() {
    configurar_dns
    read -p "Ingrese el nuevo dominio: " nuevo_dominio

    echo "[+] Configurando Postfix para $nuevo_dominio..."
    sudo postconf -e "mydestination = \$mydestination, $nuevo_dominio, mail.$nuevo_dominio"

    echo "[+] Configurando Dovecot..."
    sudo bash -c "cat > /etc/dovecot/conf.d/10-mail.conf <<EOF
mail_location = maildir:~/Maildir
namespace inbox {
  inbox = yes
}
EOF"

    echo "[+] Agregando dominio a RainLoop..."
    sudo -u www-data php /var/www/html/rainloop/data/_data_/_default_/admin.php \
        --set-domain --name="$nuevo_dominio" \
        --imap-server="localhost" --imap-port="143" --imap-secure="No" \
        --smtp-server="localhost" --smtp-port="25" --smtp-secure="No" --smtp-auth="On"

    echo "[+] Dominio $nuevo_dominio agregado correctamente."
}
# Función para verificar y configurar autenticación en Dovecot
configurar_dovecot() {
    echo "[+] Configurando autenticación PAM en Dovecot..."
    sudo sed -i 's/^#\?disable_plaintext_auth.*/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
    sudo sed -i 's/^#\?auth_mechanisms.*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf
    grep -qxF '!include auth-system.conf.ext' /etc/dovecot/conf.d/10-auth.conf || echo '!include auth-system.conf.ext' | sudo tee -a /etc/dovecot/conf.d/10-auth.conf

    echo "[+] Configurando Postfix para usar Dovecot como autenticador..."
    sudo bash -c "cat > /etc/dovecot/conf.d/10-master.conf <<EOF
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF"
}

# Función para verificar y configurar autenticación SASL en Postfix
configurar_postfix_sasl() {
    echo "[+] Configurando autenticación SASL en Postfix..."
    sudo postconf -e "smtpd_sasl_type = dovecot"
    sudo postconf -e "smtpd_sasl_path = private/auth"
    sudo postconf -e "smtpd_sasl_auth_enable = yes"
    sudo postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination"
}

# Función para configurar el servidor DNS
configurar_dns

# Inicio de configuración
read -p "Ingrese el nombre del dominio: " domain_name

echo "[+] Actualizando paquetes..."
sudo apt update -y && sudo apt upgrade -y

echo "[+] Configurando Postfix..."
echo "postfix postfix/main_mailer_type string Internet Site" | sudo debconf-set-selections
echo "postfix postfix/mailname string $domain_name" | sudo debconf-set-selections

sudo apt install -y postfix dovecot-core dovecot-pop3d dovecot-imapd apache2 php php-mbstring php-xml unzip php-curl

# Configurar Postfix
sudo postconf -e "myhostname = mail.$domain_name"
sudo postconf -e "mydomain = $domain_name"
sudo postconf -e "myorigin = /etc/mailname"
sudo postconf -e "inet_interfaces = all"
sudo postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
sudo postconf -e "home_mailbox = Maildir/"

# Configurar Dovecot
sudo bash -c "cat > /etc/dovecot/conf.d/10-mail.conf <<EOF
mail_location = maildir:~/Maildir
namespace inbox {
  inbox = yes
}
EOF"

# Instalar RainLoop
cd /var/www/html || exit
sudo rm -rf squirrelmail*
sudo wget https://www.rainloop.net/repository/webmail/rainloop-latest.zip -O rainloop.zip
sudo unzip rainloop.zip -d rainloop
sudo chown -R www-data:www-data rainloop
sudo chmod -R 755 rainloop

# Configurar Apache
sudo bash -c 'cat > /etc/apache2/conf-available/rainloop.conf <<EOF
Alias /rainloop /var/www/html/rainloop
<Directory /var/www/html/rainloop>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF'

sudo a2enconf rainloop
sudo systemctl reload apache2
read -p "Ingrese la dirección IP del servidor de correo (usada por IMAP y SMTP): " mail_ip

echo "[+] Agregando dominio por defecto $domain_name a RainLoop..."
sudo -u www-data php /var/www/html/rainloop/data/_data_/_default_/admin.php \
    --set-domain --name="$domain_name" \
    --imap-server="$mail_ip" --imap-port="143" --imap-secure="No" \
    --smtp-server="$mail_ip" --smtp-port="25" --smtp-secure="No" --smtp-auth="On"

# Configurar Postfix y Dovecot
echo "[+] Aplicando configuraciones adicionales..."
configurar_dovecot
configurar_postfix_sasl

# Reiniciar servicios
echo "[+] Reiniciando servicios..."
sudo systemctl restart postfix dovecot apache2

echo "[+] Instalación completada. Accede a http://$domain_name/rainloop para usar RainLoop."

# Menú de opciones
while true; do
    echo -e "\n----- MENÚ -----"
    echo "1. Agregar usuario de correo"
    echo "2. Eliminar usuario de correo"
    echo "3. Listar usuarios de correo"
    echo "4. Verificar si un usuario existe"
    echo "5. Agregar nuevo dominio"
    echo "6. Salir"
    read -p "Seleccione una opción: " opcion
    case $opcion in
        1) agregar_usuario ;;
        2) eliminar_usuario ;;
        3) listar_usuarios ;;
        4) verificar_usuario ;;
        5) agregar_dominio ;;
        6) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida" ;;
    esac
done
