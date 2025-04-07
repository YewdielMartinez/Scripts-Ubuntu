#!/bin/bash

# Creación de variables
FTP_ROOT="/srv/ftp"
GROUP1="reprobados"
GROUP2="recursadores"
GENERAL="general"
ANON="anon"
PROFTPD_CONF="/etc/proftpd/proftpd.conf"
TLS_CONF="/etc/proftpd/tls.conf"
CERT_FILE="/etc/ssl/private/proftpd.pem"

# Función para instalar y configurar ProFTPD
install_proftpd() {
    echo "📦 Instalando ProFTPD y acl..."
    apt update && apt install -y proftpd acl

    echo "⚙  Configurando ProFTPD..."
    sed -i 's/# DefaultRoot/DefaultRoot/g' "$PROFTPD_CONF"
    sed -i 's/# RequireValidShell/RequireValidShell/g' "$PROFTPD_CONF"

    echo "🚠 Habilitando modo pasivo en ProFTPD..."
    echo -e "\nPassivePorts 49152 65534" >> "$PROFTPD_CONF"

    echo "👥 Creando grupos..."
    getent group "$GROUP1" || groupadd "$GROUP1"
    getent group "$GROUP2" || groupadd "$GROUP2"

    echo "📂 Creando directorios FTP..."
    mkdir -p "$FTP_ROOT/$GENERAL" "$FTP_ROOT/$GROUP1" "$FTP_ROOT/$GROUP2" "$FTP_ROOT/usuarios"
    mkdir -p "$FTP_ROOT/$ANON"

    echo "🔑 Configurando permisos..."
    chown -R root:root "$FTP_ROOT"
    chmod 755 "$FTP_ROOT"
    chown -R root:root "$FTP_ROOT/$GENERAL"
    chmod 777 "$FTP_ROOT/$GENERAL"
    chown -R root:"$GROUP1" "$FTP_ROOT/$GROUP1"
    chmod 775 "$FTP_ROOT/$GROUP1"
    chown -R root:"$GROUP2" "$FTP_ROOT/$GROUP2"
    chmod 775 "$FTP_ROOT/$GROUP2"

    mkdir -p "$FTP_ROOT/$ANON/general"
    mount --bind "$FTP_ROOT/$GENERAL" "$FTP_ROOT/$ANON/general"

    cat <<EOF > /etc/proftpd/conf.d/anonymous.conf
<Anonymous $FTP_ROOT/$ANON>
    User                ftp
    Group               nogroup
    UserAlias           anonymous ftp
    <Directory general>
        <Limit WRITE>
            DenyAll
        </Limit>
        <Limit READ>
            AllowAll
        </Limit>
    </Directory>
</Anonymous>
EOF

    echo "📜 Configurando reglas de ProFTPD..."
    cat <<EOF >> "$PROFTPD_CONF"

# Los usuarios inician en su carpeta personal (enjaulados en ~)
DefaultRoot ~
EOF

    read -p "¿Deseas activar SSL/TLS en ProFTPD? (s/n): " ENABLE_SSL
    if [[ "$ENABLE_SSL" =~ ^[sS]$ ]]; then
        echo "🔐 Configurando SSL/TLS para ProFTPD..."
        # Instalar el módulo TLS (crypto) necesario
        apt install -y proftpd-mod-crypto
	sed -i 's/^#\s*\(LoadModule mod_tls\.c\)/\1/' /etc/proftpd/modules.conf
        mkdir -p /etc/ssl/private
        echo "🌍 Ingresa la información para el certificado SSL:"
        while true; do
            read -p "Código de país (2 letras, por ejemplo, MX): " C
            if [[ "$C" =~ ^[a-zA-Z]{2}$ ]]; then
                C=${C^^}  # Convertir a mayúsculas
                break
            else
                echo "❌ Error: Ingresa solo dos letras para el código de país."
            fi
        done

        # Declaración del arreglo asociativo (requiere Bash 4 o superior)
        declare -A SSL_FIELDS=(
            ["ST"]="Estado o provincia"
            ["L"]="Ciudad o localidad"
            ["O"]="Organización (nombre de la empresa)"
            ["OU"]="Unidad organizativa (por ejemplo, departamento de las TI)"
            ["CN"]="Nombre común (dominio o IP del servidor)"
        )

        for key in "${!SSL_FIELDS[@]}"; do
            while true; do
                read -p "${SSL_FIELDS[$key]}: " value
                if [[ -n "$value" ]]; then
                    declare "$key"="$value"
                    break
                else
                    echo "❌ Error: No puedes dejar este campo vacío."
                fi
            done
        done

        # Generar certificado autofirmado
        openssl req -x509 -nodes -newkey rsa:2048 -keyout "$CERT_FILE" -out "$CERT_FILE" -days 3650 \
            -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=$CN"

        echo "📄 Configurando archivos de ProFTPD..."
        # Asegurar que en proftpd.conf se incluya tls.conf (descomentando la línea si es necesario)
        sed -i 's@^#\s*Include /etc/proftpd/tls.conf@Include /etc/proftpd/tls.conf@g' "$PROFTPD_CONF"

        # Crear o sobrescribir el archivo tls.conf con la configuración recomendada
        cat <<EOF > "$TLS_CONF"
<IfModule mod_tls.c>
    TLSEngine                 on
    TLSLog                    /var/log/proftpd/tls.log
    TLSProtocol               TLSv1.2 TLSv1.3
    TLSRSACertificateFile     $CERT_FILE
    TLSRSACertificateKeyFile  $CERT_FILE
    TLSRequired               on
</IfModule>
EOF

        # Asignar permisos adecuados al archivo tls.conf
        chown root:root "$TLS_CONF"
        chmod 644 "$TLS_CONF"

        echo "✅ SSL/TLS habilitado correctamente."
    fi

    echo "🔄 Reiniciando ProFTPD..."
    systemctl restart proftpd

    echo "🎉 Configuración completada con éxito."
}

# Función para crear usuarios
create_users() {
    echo -e "\n👤 ¿Cuántos usuarios deseas crear?"
    read -r NUM_USERS

    if ! [[ "$NUM_USERS" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Debes ingresar un número válido."
        return
    fi

    for ((i=1; i<=NUM_USERS; i++)); do
        echo -e "\n📝 Creando usuario $i..."
        while true; do
            read -p "Nombre de usuario: " USERNAME
            USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')
            if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
                echo "Error: Nombre de usuario inválido."
                continue
            fi
            break
        done

        while true; do
            read -s -p "Contraseña: " PASSWORD
            echo ""
            read -s -p "Confirmar contraseña: " PASSWORD_CONFIRM
            echo ""

            if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
                echo "❌ Las contraseñas no coinciden. Inténtalo de nuevo."
                continue
            fi

            if [ ${#PASSWORD} -lt 8 ]; then
                echo "❌ La contraseña debe tener al menos 8 caracteres."
                continue
            fi

            if ! [[ "$PASSWORD" =~ [0-9] ]]; then
                echo "❌ La contraseña debe contener al menos un número."
                continue
            fi

            if ! [[ "$PASSWORD" =~ [A-Z] ]]; then
                echo "❌ La contraseña debe contener al menos una letra mayúscula."
                continue
            fi

            if ! [[ "$PASSWORD" =~ [a-z] ]]; then
                echo "❌ La contraseña debe contener al menos una letra minúscula."
                continue
            fi

            if ! [[ "$PASSWORD" =~ [\@\#\$\%\^\&\*\(\)\_\+\!] ]]; then
                echo "❌ La contraseña debe contener al menos un carácter especial (@, #, \$, %, ^, &, *, (, ), _, +, !)."
                continue
            fi

            break
        done

        while true; do
            read -p "Grupo ($GROUP1/$GROUP2): " group
            if [[ "$group" == "$GROUP1" || "$group" == "$GROUP2" ]]; then
                break
            else
                echo "❌ Grupo no válido. Ingresa '$GROUP1' o '$GROUP2'."
            fi
        done

        if id "$USERNAME" &>/dev/null; then
            echo "⚠  El usuario $USERNAME ya existe, saltando creación..."
            continue
        fi

        useradd -m -s /bin/false -G "$group" "$USERNAME"
        usermod -d "$FTP_ROOT/usuarios/$USERNAME" "$USERNAME"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME/$USERNAME"
        chown "$USERNAME:$group" "$FTP_ROOT/usuarios/$USERNAME/$USERNAME"
        chmod 700 "$FTP_ROOT/usuarios/$USERNAME/$USERNAME"
        chown -R "$USERNAME:$group" "$FTP_ROOT/usuarios/$USERNAME"
        chmod 770 "$FTP_ROOT/usuarios/$USERNAME"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME/general"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME/$group"
        mount --bind "$FTP_ROOT/$GENERAL" "$FTP_ROOT/usuarios/$USERNAME/general"
        mount --bind "$FTP_ROOT/$group" "$FTP_ROOT/usuarios/$USERNAME/$group"
        echo "$USERNAME:$PASSWORD" | chpasswd

        echo "✅ Usuario $USERNAME creado en el grupo $group."
    done

    echo "🔄 Reiniciando ProFTPD..."
    systemctl restart proftpd

    echo "🎉 Usuarios creados con éxito."
}

# Menú interactivo
while true; do
    echo -e "\n📋 Configurar servidor FTP Version 11.01"
    echo -e "\n📋 Hoy vale 6 verdad :)"
    echo "1. Instalar y configurar FTP"
    echo "2. Crear usuarios"
    echo "3. Salir"
    read -p "Selecciona una opción: " option

    case $option in
        1)
            install_proftpd
            ;;
        2)
            create_users
            ;;
        3)
            echo "👋 Saliendo..."
            break
            ;;
        *)
            echo "❌ Opción no válida. Inténtalo de nuevo."
            ;;
    esac
done