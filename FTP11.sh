#!/bin/bash

# Variables
FTP_ROOT="/srv/ftp"
GROUP1="reprobados"
GROUP2="recursadores"
GENERAL="general"
ANON="anon"
PROFTPD_CONF="/etc/proftpd/proftpd.conf"

# Función para instalar y configurar ProFTPD
install_proftpd() {
    echo "📦 Instalando FTP y acl..."
    apt update && apt install -y proftpd acl

    echo "⚙  Configurando FTP..."
    sed -i 's/# DefaultRoot/DefaultRoot/g' $PROFTPD_CONF
    sed -i 's/# RequireValidShell/RequireValidShell/g' $PROFTPD_CONF

    echo "Habilitando modo pasivo en FTP..."
    echo -e "\nPassivePorts 49152 65534" >> $PROFTPD_CONF

    echo "👥 Creando grupos(reprobados o recursadores )..."
    getent group $GROUP1 || groupadd $GROUP1
    getent group $GROUP2 || groupadd $GROUP2

    echo "📂 Creando directorios FTP..."
    mkdir -p "$FTP_ROOT/$GENERAL" "$FTP_ROOT/$GROUP1" "$FTP_ROOT/$GROUP2" "$FTP_ROOT/usuarios"
    mkdir -p "$FTP_ROOT/$ANON"

    echo "🔑 Configurando permisos..."
    chown -R root:root "$FTP_ROOT"
    chmod 755 "$FTP_ROOT"
    chown -R root:root "$FTP_ROOT/$GENERAL"
    chmod 777 "$FTP_ROOT/$GENERAL"
    chown -R root:$GROUP1 "$FTP_ROOT/$GROUP1"
    chmod 775 "$FTP_ROOT/$GROUP1"
    chown -R root:$GROUP2 "$FTP_ROOT/$GROUP2"
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
    cat <<EOF >> $PROFTPD_CONF

# Los usuarios inician en su carpeta personal (enjaulados en ~)
DefaultRoot ~
EOF

    echo "🔄 Reiniciando ProFTPD..."
    systemctl restart proftpd

    echo "🎉 Configuración completada con éxito."
}

# Función para crear usuarios
create_users() {
    echo -e "\n👤 ¿Cuántos usuarios deseas crear?(Ingresa numero porfavor no intentes otra cosa porfavor )"
    read -r NUM_USERS

    if ! [[ "$NUM_USERS" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Debes ingresar un número válido."
        return
    fi

    for ((i=1; i<=NUM_USERS; i++)); do
        echo -e "\n📝 Creando usuario $i..."

       while true; do
        read -p "Nombre de usuario(Favor de ingresar un nombre de usuario sin puntos ni numeros ni signos raros se una buena persona): " USERNAME
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
                echo "❌ La contraseña debe contener al menos un carácter especial (@, #, $, %, ^, &, *, (, ), _, +, !)."
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