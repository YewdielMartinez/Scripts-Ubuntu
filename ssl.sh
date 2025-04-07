#!/bin/bash

# Puertos permitidos (excluyendo puertos comunes reservados).
allowed_ports=(80 1024 8080 2019 3000 5000 8081 8443)
allowed_https_ports=(443 8443)  # Puertos HTTPS permitidos

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


# Función para preguntar si activar SSL
ssl_activate() {
    while true; do
        read -p "¿Deseas activar SSL? (si/no): " respuesta
        case $respuesta in
            [Ss]* ) echo "si"; return 0;;
            [Nn]* ) echo "no"; return 1;;
            * ) echo "Por favor, responde 'si' o 'no'.";;
        esac
    done
}


# Validar que el puerto sea un número válido, exista y no esté en uso
validate_port() {
    local port=$1

    # Verificar que el puerto sea un número y esté dentro del rango válido
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: El puerto debe ser un número."
        return 1
    fi

    # Verificar que el puerto esté permitido
    if [[ ! " ${allowed_ports[@]} " =~ " $port " ]]; then
        echo "❌ Error: El puerto $port no está permitido. Puertos válidos: ${allowed_ports[*]}"
        return 1
    fi

    # Verificar que el puerto no esté en uso
if ss -tuln | grep -q ":$port "; then
    echo "❌ Error: El puerto $port ya está en uso."
    return 1
fi


    return 0
}

# Verificar si el puerto 80 está en uso por otro servicio
check_port_80_usage() {
    if lsof -i:80 &> /dev/null; then
        echo "❌ El puerto 80 ya está en uso. Esto puede causar problemas con Nginx."
        return 1
    else
        echo "✅ El puerto 80 está libre."
        return 0
    fi
}

# Obtener la última versión estable y de desarrollo de Tomcat desde la web oficial
get_latest_tomcat_versions() {
    local stable_url="https://tomcat.apache.org/download-90.cgi"
    local dev_url="https://tomcat.apache.org/download-11.cgi"

    # Extraer la versión más reciente del formato de enlaces de descarga
    local stable_version=$(curl -s $stable_url | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)
    local dev_version=$(curl -s $dev_url | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)

    echo "$stable_version $dev_version"
}



# Instalar Tomcat
install_tomcat() {
    local puerto=$1
    local tomcat_home="/opt/tomcat"

    # Obtener la última versión de Tomcat
    read stable_version dev_version <<< $(get_latest_tomcat_versions)

    echo "\n📥 Versiones disponibles para instalar:"
    echo "1) Estable: $stable_version"
    echo "2) Desarrollo: $dev_version"

    while true; do
        read -p "Seleccione una versión [1-2]: " version_choice
        case $version_choice in
            1) version=$stable_version; 
	       break ;;
            2) version=$dev_version; 
               break ;;
            *) echo "❌ Opción no válida. Intente de nuevo."  
	       ;;
        esac
    done

    # Verificar si Java está instalado
    if ! command -v java &>/dev/null; then
        echo "Instalando Java..."
        apt update && apt install -y default-jdk || { echo "Error al instalar Java"; exit 1; }
    fi

    if [ -d "$tomcat_home" ]; then
        echo "Tomcat ya está instalado en $tomcat_home."
        read -p "¿Desea reinstalar Tomcat? ("S" para "Sí" y cualquier otra cosa para "No" :) ): " respuesta
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



# Preguntar si activar SSL
    ssl_activate=$(ssl_activate)
    
    # Si SSL está activado, pedir puerto HTTPS
    if [[ "$ssl_activate" == "si" ]]; then
        read -p "Ingrese el puerto HTTPS para Tomcat (por defecto 8443): " puerto_https
        puerto_https=${puerto_https:-8443}

        # Validar el puerto HTTPS
        if ! validate_https_port "$puerto_https"; then
            echo "Usando puerto HTTPS por defecto: 8443"
            puerto_https=8443
        fi
    fi


    # Configurar puerto
    echo "⚙ Configurando Tomcat para usar el puerto $puerto..."
    if [[ "$ssl_activate" == "si" ]]; then
        # Añadir configuración para SSL en server.xml de Tomcat
        sed -i "s/port=\"8080\"/port=\"$puerto\"/" $tomcat_home/conf/server.xml
        sed -i "/<\/Service>/i \
        <Connector port=\"$puerto_https\" protocol=\"HTTP/1.1\" SSLEnabled=\"true\" \
        maxThreads=\"150\" scheme=\"https\" secure=\"true\" \
        clientAuth=\"false\" sslProtocol=\"TLS\" \
        keystoreFile=\"\/opt\/tomcat\/conf\/keystore.jks\" \
        keystorePass=\"changeit\" />" $tomcat_home/conf/server.xml

        echo "SSL activado. Tomcat escuchará en el puerto $puerto_https para HTTPS."

        # Crear un archivo de almacén de claves (keystore) autofirmado
        if [[ ! -f "$tomcat_home/conf/keystore.jks" ]]; then
            echo "Generando keystore autofirmado..."
            keytool -genkey -keyalg RSA -alias tomcat -keystore $tomcat_home/conf/keystore.jks -storepass changeit -validity 3650 -keysize 2048 -dname "CN=localhost, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=US"
        fi
    else
        sed -i "s/port=\"8080\"/port=\"$puerto\"/" $tomcat_home/conf/server.xml
        echo "SSL no activado. Tomcat escuchará solo en el puerto $puerto."
    fi

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
            echo "✅ Tomcat $version instalado y funcionando en el puerto $puerto"
            echo "🌐 Puede acceder a Tomcat en: http://localhost:$puerto o http:127.0.1.1:$puerto. Si ingresa desde un cliente puede acceder en: http://ip_servidor:$puerto"
        else
            echo "❌ Error al iniciar Tomcat. Verifique el log:"
            tail -n 20 $tomcat_home/logs/catalina.out
            systemctl status tomcat --no-pager
        fi
    else
        echo "Advertencia: systemctl no está disponible, Tomcat no se ejecutará como servicio."
    fi
}

# Obtener la última versión estable y de desarrollo de Caddy desde GitHub
get_latest_caddy_versions() {
    local stable_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    local dev_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases | grep -oP '"tag_name": "\K[^"]+' | grep beta | head -1)

    echo "$stable_version $dev_version"
}

# Instalar Caddy
install_caddy() {
    local puerto=$1

    # Obtener la última versión de Caddy
    read stable_version dev_version <<< $(get_latest_caddy_versions)

    echo "\n📥 Versiones disponibles para instalar:"
    echo "1) Estable: $stable_version"
    echo "2) Desarrollo (Testing): $dev_version"
    

    while true; do
	read -p "Seleccione una opción [1-2]: " version_choice
    	case $version_choice in
            1) 
            	repo_name="stable"
            	key_url='https://dl.cloudsmith.io/public/caddy/stable/gpg.key'
            	repo_url='https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt'
		break
            	;;
            2) 
            	repo_name="testing"
            	key_url='https://dl.cloudsmith.io/public/caddy/testing/gpg.key'
            	repo_url='https://dl.cloudsmith.io/public/caddy/testing/debian.deb.txt'
		break
            	;;
            *) 
            	echo "❌ Opción no válida. Intente de nuevo." 
            	;;
    	esac
    done

    echo "\n📥 Instalando Caddy versión $repo_name..."

    # Instalar dependencias necesarias
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    
    # Agregar clave GPG y repositorio
    curl -1sLf "$key_url" | sudo gpg --dearmor -o /usr/share/keyrings/caddy-$repo_name-archive-keyring.gpg
    curl -1sLf "$repo_url" | sudo tee /etc/apt/sources.list.d/caddy-$repo_name.list
    
    # Actualizar repositorios e instalar Caddy
    sudo apt update
    sudo apt install -y caddy

ssl_activate=$(ssl_activate)
    if [[ "$ssl_activate" == "si" ]]; then
        read -p "Ingrese el puerto HTTPS para Caddy (por defecto 443): " puerto_https
        puerto_https=${puerto_https:-443}
        if ! validate_https_port "$puerto_https"; then
            echo "Usando puerto HTTPS por defecto: 443"
            puerto_https=443
        fi
        ssl_config="    tls internal"
        # Crear certificados autofirmados (solo si es necesario)
        sudo mkdir -p /etc/caddy/certs
        sudo openssl req -x509 -newkey rsa:2048 -keyout /etc/caddy/certs/caddy.key -out /etc/caddy/certs/caddy.crt -days 365 -nodes -subj "/CN=localhost"
    else
        ssl_config=""
        puerto_https=""
    fi


    echo "⚙ Configurando Caddy para usar el puerto $puerto..."
    
    # Crear configuración básica de Caddy
    if [[ "$ssl_activate" == "si" ]]; then
        cat > /etc/caddy/Caddyfile << EOF

http://127.0.1.1:$puerto {
    respond "Caddy funcionando en HTTP en el puerto $puerto"
}

https://127.0.1.1:$puerto_https {
root * /var/www/html
file_server
$ssl_config
    respond "Caddy funcionando en HTTPS en el puerto $puerto_https"
}
EOF
    else
        cat > /etc/caddy/Caddyfile << EOF
http://127.0.1.1:$puerto {
    respond "Caddy funcionando en HTTP en el puerto $puerto"
}
EOF
    fi
    # Ajustar permisos y reiniciar Caddy
    sudo chown caddy:caddy /etc/caddy/Caddyfile
    sudo systemctl restart caddy
    sudo systemctl enable caddy

    sleep 3 # Esperar a que Caddy se inicie

    if systemctl is-active --quiet caddy; then
        echo "✅ Caddy $repo_name instalado y funcionando en el puerto $puerto"
        echo "🌐 Puede acceder a Caddy en: http://localhost:$puerto o http://127.0.0.1:$puerto"
        if [[ "$ssl_activate" == "si" ]]; then
            echo "🌐 Acceda mediante https://localhost:$puerto (certificado autofirmado)"
        fi
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
    local puerto=$1

    # Obtener la última versión de Nginx
    read stable_version dev_version <<< $(get_latest_nginx_versions)

    echo "\n📥 Versiones disponibles para instalar:"
    echo "1) Estable: $stable_version"
    echo "2) Desarrollo (Mainline): $dev_version"

    while true; do
        read -p "Seleccione una opción [1-2]: " version_choice
        case $version_choice in
            1) version=$stable_version; break ;;
            2) version=$dev_version; break ;;
            *) echo "❌ Opción no válida. Intente de nuevo." ;;
        esac
    done

    # Crear directorios necesarios
    local temp_dir=$(mktemp -d)
    local nginx_tar="nginx-$version.tar.gz"
    local nginx_url="https://nginx.org/download/nginx-$version.tar.gz"

    echo "Descargando Nginx $version..."
    curl -L "$nginx_url" -o "$temp_dir/$nginx_tar"

    echo "Descomprimiendo Nginx..."
    tar -xzvf "$temp_dir/$nginx_tar" -C "$temp_dir"

    sudo apt update
    sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev

    cd "$temp_dir/nginx-$version"
    ./configure --with-http_ssl_module
    make
    sudo make install

    # Configuración de SSL opcional
    ssl_activate=$(ssl_activate)
    if [[ "$ssl_activate" == "si" ]]; then
        read -p "Ingrese el puerto HTTPS para Nginx (por defecto 443): " puerto_https
        puerto_https=${puerto_https:-443}
        sudo mkdir -p /etc/nginx/certs
        sudo openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/certs/nginx.key -out /etc/nginx/certs/nginx.crt -days 365 -nodes -subj "/CN=localhost"
        ssl_config="\n        listen $puerto_https ssl;\n        ssl_certificate /etc/nginx/certs/nginx.crt;\n        ssl_certificate_key /etc/nginx/certs/nginx.key;"
    else
        ssl_config=""
        puerto_https=""
    fi

    # Configurar Nginx
    echo "Configurando Nginx para usar el puerto $puerto..."
    sudo tee /usr/local/nginx/conf/nginx.conf > /dev/null << EOF
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen $puerto;
        location / {
            root   /usr/local/nginx/html;
            index  index.html index.htm;
        }
        $ssl_config
    }
}
EOF

    echo "Agregando Nginx al PATH..."
    echo 'export PATH=$PATH:/usr/local/nginx/sbin' >> ~/.bashrc
    source ~/.bashrc

    echo "Iniciando Nginx..."
    sudo /usr/local/nginx/sbin/nginx

    echo "✅ Nginx instalado y funcionando en el puerto $puerto."
    echo "🌐 Puede acceder a Nginx en: http://localhost:$puerto"
    [[ "$ssl_activate" == "si" ]] && echo "🌐 Acceda mediante https://localhost:$puerto_https (certificado autofirmado)"
}

# Desinstalar un servicio
uninstall_service() {
    # Crear un arreglo con solo los servicios instalados
    services=()
    
    if command -v caddy &>/dev/null; then
        services+=("Caddy")
    fi
    if [ -d "/opt/tomcat" ]; then
        services+=("Tomcat")
    fi
    if systemctl list-units --type=service | grep -q nginx; then
	services+=("Nginx")
    fi


    # Si no hay ninguno instalado, informar y salir
    if [ ${#services[@]} -eq 0 ]; then
        echo "No hay servicios instalados para desinstalar."
        return
    fi

    while true; do
        # Mostrar los servicios instalados disponibles para desinstalar
        echo "Selecciona un servicio para desinstalar:"
        for i in "${!services[@]}"; do
            echo "$((i+1)). ${services[$i]}"
        done
        
        # Leer la opción del usuario
        read -p "Introduce el número del servicio que deseas desinstalar: " choice
        
        # Validar si la opción es válida (debe ser un número dentro del rango)
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#services[@]} ]; then
            service="${services[$((choice-1))]}"
            # Confirmar la desinstalación del servicio
            read -p "¿Estás seguro de que quieres desinstalar el servicio '$service'? (S para Sí y cualquier otra cosa para No): " confirm
            if [[ "$confirm" =~ ^[Ss]$ ]]; then
                # Detener el servicio
                echo "Deteniendo el servicio $service..."
                sudo systemctl stop "$service"

                # Deshabilitar el servicio
                echo "Deshabilitando el servicio $service..."
                sudo systemctl disable "$service"
                
                # Desinstalar el servicio dependiendo de cuál haya sido seleccionado
                case $service in
                    "Caddy")
                        echo "Desinstalando Caddy..."
                        sudo apt-get purge -y caddy
                        ;;
                    "Tomcat")
                        echo "Desinstalando Tomcat..."
	                
                        # Eliminar el archivo del servicio y recargar systemd
                        sudo rm -f /etc/systemd/system/tomcat.service
                        sudo systemctl daemon-reload
                        # Eliminar el directorio de Tomcat
                        sudo rm -rf /opt/tomcat
                        # Opcional: eliminar el usuario "tomcat" si existe
                        if id -u tomcat &>/dev/null; then
                            sudo userdel -r tomcat
                        fi
                        ;;
                    "Nginx")
                        echo "Desinstalando Nginx..."
                        sudo systemctl stop nginx
                        sudo systemctl disable nginx
                        sudo apt remove --purge -y nginx nginx-common nginx-full
                        sudo rm -rf /etc/nginx /var/www/html /var/log/nginx /usr/share/nginx
                        sudo pkill -f nginx || true
                        sudo systemctl daemon-reload
                        sudo systemctl reset-failed
                        ;;
                    *)
                        echo "Servicio no reconocido."
                        ;;
                esac

                # Limpiar dependencias no necesarias
                echo "Limpiando dependencias no necesarias..."
                sudo apt-get autoremove -y
                echo "✅ El servicio '$service' ha sido desinstalado correctamente."
                break
            else
                echo "Desinstalación cancelada para el servicio '$service'."
                break
            fi
        else
            echo "Opción inválida. Por favor, ingresa un número entre 1 y ${#services[@]}."
        fi
    done
}
main_menu_ssl() {
    while true; do
        echo "========================================"
        echo "       Instalador de Servidores SSL"
        echo "========================================"
        echo "1) Instalar Nginx"
        echo "2) Instalar Tomcat"
        echo "3) Instalar Caddy"
        echo "4) Desinstalar un servicio"
        echo "5) Salir"
        echo "========================================"
        read -p "Seleccione una opción [1-5]: " choice

        case $choice in
            1)
                while true; do
                    echo "Puertos permitidos para evitar utilizar alguno reservado: ${allowed_ports[*]}"
                    read -p "Ingrese el puerto para Nginx (por defecto 80): " puerto
                    puerto=${puerto:-80}
                    if validate_port "$puerto"; then
                        install_nginx "$puerto"
                        break
                    else
                        echo "❌ Puerto no válido. Intente de nuevo."
                    fi
                done
                ;;
            2)
                while true; do
                    echo "Puertos permitidos para evitar utilizar alguno reservado: ${allowed_ports[*]}"
                    read -p "Ingrese el puerto para Tomcat (por defecto 8080): " puerto
                    puerto=${puerto:-8080}
                    if validate_port "$puerto"; then
                        install_tomcat "$puerto"
                        break
                    else
                        echo "❌ Puerto no válido. Intente de nuevo."
                    fi
                done
                ;;
            3)
                while true; do
                    echo "Puertos permitidos para evitar utilizar alguno reservado: ${allowed_ports[*]}"
                    read -p "Ingrese el puerto para Caddy (por defecto 2019): " puerto
                    puerto=${puerto:-2019}
                    if validate_port "$puerto"; then
                        install_caddy "$puerto"
                        break
                    else
                        echo "❌ Puerto no válido. Intente de nuevo."
                    fi
                done
                ;;
            4)
                uninstall_service
                ;;
            5)
                echo "👋 Saliendo del instalador..."
                exit 0
                ;;
            *)
                echo "❌ Opción no válida. Intente nuevamente."
                ;;
        esac
    done
}

# Llamar al menú principal
main_menu_ssl