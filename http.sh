#!/bin/bash

# Verificar si wget está instalado
if ! command -v wget &> /dev/null; then
    echo "Error: wget no está instalado. Instálalo con 'sudo apt install wget'."
    exit 1
fi

# Verificar si curl está instalado
if ! command -v curl &> /dev/null; then
    echo "Error: curl no está instalado. Instálalo con 'sudo apt install curl'."
    exit 1
fi

get_latest_tomcat_versions() {
    local stable_url="https://tomcat.apache.org/download-90.cgi"
    local dev_url="https://tomcat.apache.org/download-11.cgi"

    # Extraer la versión más reciente del formato de enlaces de descarga
    local stable_version=$(curl -s $stable_url | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)
    local dev_version=$(curl -s $dev_url | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)

    echo "$stable_version $dev_version"
}

# Validar que el puerto sea un número y no esté en uso
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: El puerto debe ser un número."
        return 1
    fi

    if lsof -i:"$port" &> /dev/null; then
        echo "❌ Error: El puerto $port ya está en uso."
        return 1
    fi

    return 0
}

# Instalar Tomcat
install_tomcat() {
    local puerto=$1
    local tomcat_home="/opt/tomcat"

    # Obtener la última versión de Tomcat
    read stable_version dev_version <<< $(get_latest_tomcat_versions)

    echo "Versiones disponibles:"
    echo "1) Estable: $stable_version"
    echo "2) Desarrollo: $dev_version"

    while true; do
        read -p "Seleccione una versión [1-2]: " version_choice
        case $version_choice in
            1) version=$stable_version; break ;;
            2) version=$dev_version; break ;;
            *) echo "Opción no válida. Intente de nuevo." ;;
        esac
    done

    # Verificar si Java está instalado
    if ! command -v java &>/dev/null; then
        echo "Instalando Java..."
        apt update && apt install -y default-jdk || { echo "Error al instalar Java"; exit 1; }
    fi

    if [ -d "$tomcat_home" ]; then
        echo "Tomcat ya está instalado en $tomcat_home."
        read -p "¿Desea reinstalar Tomcat? (s/n): " respuesta
        if [[ "$respuesta" != "s" && "$respuesta" != "S" ]]; then
            echo "Omitiendo instalación de Tomcat."
            return
        fi

        if [ -f "$tomcat_home/bin/shutdown.sh" ]; then
            echo "Deteniendo Tomcat..."
            $tomcat_home/bin/shutdown.sh
            sleep 2
        fi

        echo "Eliminando instalación anterior de Tomcat..."
        rm -rf $tomcat_home
    fi

    mkdir -p $tomcat_home
    cd /tmp

    # Construir la URL de descarga
    local tomcat_major=$(echo "$version" | cut -d'.' -f1)
    local tomcat_url="https://downloads.apache.org/tomcat/tomcat-$tomcat_major/v$version/bin/apache-tomcat-$version.tar.gz"

    echo "Descargando Tomcat versión $version..."
    if ! curl -fsSL "$tomcat_url" -o tomcat.tar.gz; then
        echo "Error al descargar Tomcat. Verifique la URL o su conexión a Internet."
        return 1
    fi

    echo "Extrayendo archivos..."
    tar xf tomcat.tar.gz -C $tomcat_home --strip-components=1 && rm tomcat.tar.gz

    # Crear usuario tomcat si no existe
    if ! id -u tomcat &>/dev/null; then
        echo "Creando usuario tomcat..."
        useradd -m -d $tomcat_home -U -s /bin/false tomcat
    fi

    # Configurar permisos
    chown -R tomcat:tomcat $tomcat_home
    chmod +x $tomcat_home/bin/*.sh

    # Configurar puerto
    echo "Configurando Tomcat para usar el puerto $puerto..."
    sed -i "s/port=\"8080\"/port=\"$puerto\"/" $tomcat_home/conf/server.xml

    # Crear servicio systemd con reinicio automático
    if command -v systemctl &>/dev/null; then
        echo "Creando servicio systemd para Tomcat..."
        cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="CATALINA_HOME=$tomcat_home"
Environment="CATALINA_BASE=$tomcat_home"
Environment="CATALINA_PID=$tomcat_home/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M"

ExecStart=$tomcat_home/bin/startup.sh
ExecStop=$tomcat_home/bin/shutdown.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        # Recargar systemd y habilitar servicio
        systemctl daemon-reload
        systemctl enable tomcat
        systemctl start tomcat

        sleep 3 # Esperar a que Tomcat se inicie

        if systemctl is-active --quiet tomcat; then
            echo "✓ Tomcat $version instalado y funcionando en el puerto $puerto"
            echo "Puede acceder a Tomcat en: http://localhost:$puerto"
        else
            echo "✗ Error al iniciar Tomcat. Verifique el log:"
            tail -n 20 $tomcat_home/logs/catalina.out
            systemctl status tomcat --no-pager
        fi
    else
        echo "Advertencia: systemctl no está disponible, Tomcat no se ejecutará como servicio."
    fi
}
get_latest_caddy_versions() {
    local stable_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    local dev_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases | grep -oP '"tag_name": "\K[^"]+' | grep beta | head -1)

    echo "$stable_version $dev_version"
}

install_caddy() {
    local puerto=$1

    # Obtener las últimas versiones
    read stable_version dev_version <<< $(get_latest_caddy_versions)

    echo "\n📥 Seleccione la versión de Caddy a instalar:"
    echo "1) Estable: $stable_version"
    echo "2) Desarrollo (Testing): $dev_version"
    read -p "Seleccione una opción [1-2]: " version_choice

    case $version_choice in
        1) 
            repo_name="stable"
            key_url='https://dl.cloudsmith.io/public/caddy/stable/gpg.key'
            repo_url='https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt'
            ;;
        2) 
            repo_name="testing"
            key_url='https://dl.cloudsmith.io/public/caddy/testing/gpg.key'
            repo_url='https://dl.cloudsmith.io/public/caddy/testing/debian.deb.txt'
            ;;
        *) 
            echo "❌ Opción no válida." 
            return 1 
            ;;
    esac

    echo "\n📥 Instalando Caddy versión $repo_name..."

    # Instalar dependencias necesarias
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    
    # Agregar clave GPG y repositorio
    curl -1sLf "$key_url" | sudo gpg --dearmor -o /usr/share/keyrings/caddy-$repo_name-archive-keyring.gpg
    curl -1sLf "$repo_url" | sudo tee /etc/apt/sources.list.d/caddy-$repo_name.list
    
    # Actualizar repositorios e instalar Caddy
    sudo apt update
    sudo apt install -y caddy

    echo "⚙️ Configurando Caddy para usar el puerto $puerto..."
    
    # Crear configuración básica de Caddy
    cat > /etc/caddy/Caddyfile << EOF
{
    auto_https off
}

:$puerto {
    respond "Caddy funcionando en el puerto $puerto"
}
EOF

    # Ajustar permisos y reiniciar Caddy
    sudo chown caddy:caddy /etc/caddy/Caddyfile
    sudo systemctl restart caddy
    sudo systemctl enable caddy

    sleep 3 # Esperar a que Caddy se inicie

    if systemctl is-active --quiet caddy; then
        echo "✅ Caddy $repo_name instalado y funcionando en el puerto $puerto"
        echo "🌐 Puede acceder a Caddy en: http://localhost:$puerto"
    else
        echo "❌ Error al iniciar Caddy. Verifique el log:"
        journalctl -u caddy --no-pager | tail -n 20
        systemctl status caddy --no-pager
    fi
}


# Obtener la última versión estable y de desarrollo de Nginx desde la web oficial
get_latest_nginx_versions() {
    local url="https://nginx.org/en/download.html"

    # Obtener todas las versiones disponibles
    local versions=$(curl -s $url | grep -oP '(?<=nginx-)[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr)

    # Extraer la versión estable (números pares en el segundo segmento)
    local stable_version=$(echo "$versions" | grep -E '^[0-9]+\.([0-9]*[02468])\.[0-9]+$' | head -1)

    # Extraer la versión de desarrollo (números impares en el segundo segmento)
    local dev_version=$(echo "$versions" | grep -E '^[0-9]+\.([0-9]*[13579])\.[0-9]+$' | head -1)

    echo "$stable_version $dev_version"
}

# Descargar e instalar Nginx desde el sitio oficial
install_nginx() {
    local version=$1
    local puerto=$2

    # Crear directorios necesarios
    local temp_dir=$(mktemp -d)
    local nginx_tar="nginx-$version.tar.gz"
    local nginx_url="https://nginx.org/download/nginx-$version.tar.gz"

    echo "Descargando Nginx $version..."
    curl -L "$nginx_url" -o "$temp_dir/$nginx_tar"

    # Descomprimir el archivo
    echo "Descomprimiendo Nginx..."
    tar -xzvf "$temp_dir/$nginx_tar" -C "$temp_dir"

    # Instalar dependencias necesarias
    sudo apt update
    sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev

    # Compilar e instalar Nginx
    cd "$temp_dir/nginx-$version"
    ./configure
    make
    sudo make install

    # Configurar Nginx para usar el puerto especificado
    echo "Configurando Nginx para usar el puerto $puerto..."
    sudo sed -i "s/listen 80;/listen $puerto;/" /usr/local/nginx/conf/nginx.conf

    # Agregar /usr/local/nginx/sbin al PATH
    echo "Agregando Nginx al PATH..."

    echo 'export PATH=$PATH:/usr/local/nginx/sbin' >> ~/.bashrc
    source ~/.bashrc

    # Iniciar y habilitar el servicio
    echo "Iniciando Nginx..."
    sudo /usr/local/nginx/sbin/nginx

    echo "✓ Nginx $version instalado y ejecutándose en el puerto $puerto."
}

# Desinstalar un servicio
uninstall_service() {
    echo "Servicios instalados:"
    systemctl list-units --type=service --state=running | grep -E "tomcat|caddy|nginx" | awk '{print NR") "$1}'
    
    read -p "Ingrese el número del servicio a desinstalar: " service_number
    local service_name=$(systemctl list-units --type=service --state=running | grep -E "tomcat|caddy|nginx" | awk -v num="$service_number" 'NR==num {print $1}')
    
    if [[ -z "$service_name" ]]; then
        echo "Número inválido. Cancelando operación."
        return
    fi
    
    echo "Desinstalando $service_name..."
    systemctl stop $service_name
    systemctl disable $service_name
    rm -f /etc/systemd/system/$service_name
    systemctl daemon-reload
    echo "$service_name ha sido desinstalado."
}

# Menú principal
while true; do
    echo "========================================"
    echo "       Instalador de Servidores HTTP"
    echo "========================================"
    echo "1) Instalar Caddy"
    echo "2) Instalar Tomcat"
    echo "3) Instalar Nginx"
    echo "4) Salir"
    echo "5) Desinstalar un servicio"
    echo "========================================"
    read -p "Seleccione una opción [1-5]: " choice

    case $choice in
        1)
            read -p "Ingrese el puerto para Caddy (por defecto 2019): " puerto
            puerto=${puerto:-2019}
            if validate_port "$puerto"; then
                install_caddy "$puerto"
            fi
            ;;
        2)
            read -p "Ingrese el puerto para Tomcat (por defecto 8080): " puerto
            puerto=${puerto:-8080}
            if validate_port "$puerto"; then
                install_tomcat "$puerto"
            fi
            ;;
        3)
            # Mostrar las versiones disponibles y permitir que el usuario seleccione una
            echo "Obteniendo versiones de Nginx..."
            read stable_version dev_version <<< $(get_latest_nginx_versions)

            echo "Últimas versiones disponibles de Nginx:"
            echo "1) Estable: $stable_version"
            echo "2) Desarrollo (Mainline): $dev_version"

            # Solicitar al usuario seleccionar una versión
            read -p "Seleccione la versión que desea instalar [1-2]: " version_choice

            case $version_choice in
                1) version=$stable_version ;;
                2) version=$dev_version ;;
                *) echo "Opción no válida." ; exit 1 ;;
            esac

            # Solicitar el puerto
            read -p "Ingrese el puerto para Nginx (por defecto 80): " puerto
            puerto=${puerto:-80}
            if validate_port "$puerto"; then
                install_nginx "$version" "$puerto"
            fi
            ;;
        4)
            echo "Saliendo del instalador..."
            exit 0
            ;;
        5)
            uninstall_service
            ;;
        *)
            echo "Opción no válida. Intente nuevamente."
            ;;
    esac
done