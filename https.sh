#!/bin/bash


# Puertos permitidos (excluyendo puertos comunes reservados).
allowed_ports=(80 1024 8080 2019 3000 5000 8081)
allowed_https_ports=(443 8443 9443)  # Puertos HTTPS permitidos

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


# Validar que el puerto sea un número válido, exista y no esté en uso
validate_https_port() {
    local port=$1

    # Verificar que el puerto sea un número y esté dentro del rango válido
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: El puerto debe ser un número."
        return 1
    fi

    # Verificar que el puerto esté permitido
    if [[ ! " ${allowed_https_ports[@]} " =~ " $port " ]]; then
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



# Preguntar si activar SSL y, de ser así, solicitar el puerto HTTPS
    ssl_activate=$(ssl_activate)
    if [[ "$ssl_activate" == "si" ]]; then
        while true; do
            read -p "Ingrese el puerto HTTPS para Tomcat (por defecto 8443): " puerto_https
            puerto_https=${puerto_https:-8443}
            if validate_https_port "$puerto_https"; then
                break
            else
                echo "❌ Puerto HTTPS inválido. Intente de nuevo."
            fi
        done
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
            echo "🌐 Acceda mediante https://localhost:$puerto_https(certificado autofirmado)"
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
    	    1) version=$stable_version;
		break
            	;;
            2) version=$dev_version;
		break
            	;;
            *) echo "❌ Opción no válida. Intente de nuevo." 
            	;;
        esac
    done

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
    ./configure --with-http_ssl_module
    make
    sudo make install

    # Configurar Nginx para usar el puerto especificado
    echo "Configurando Nginx para usar el puerto $puerto..."
    sudo sed -i "s/port=\"80\"/port=\"$puerto\"/" /usr/local/nginx/conf/nginx.conf

    # Agregar /usr/local/nginx/sbin al PATH
    echo "Agregando Nginx al PATH..."

    echo 'export PATH=$PATH:/usr/local/nginx/sbin' >> ~/.bashrc
    source ~/.bashrc

    # Iniciar y habilitar el servicio
    echo "Iniciando Nginx..."
    sudo /usr/local/nginx/sbin/nginx


ssl_activate=$(ssl_activate)
    if [[ "$ssl_activate" == "si" ]]; then
        read -p "Ingrese el puerto HTTPS para Caddy (por defecto 9443): " puerto_https
        puerto_https=${puerto_https:-9443}
        if ! validate_https_port "$puerto_https"; then
            echo "Usando puerto HTTPS por defecto: 9443"
            puerto_https=9443
        fi
        ssl_config="    tls internal"
    sudo mkdir -p /usr/local/nginx/conf/ssl
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /usr/local/nginx/conf/ssl/nginx.key -out /usr/local/nginx/conf/ssl/nginx.crt -subj "/CN=localhost"

sudo tee /usr/local/nginx/conf/nginx.conf > /dev/null << 'EOF'

worker_processes 1;

events {
	worker_connections 1024;
}

http {
	include mime.types;
	default_type application/octet-stream;

	sendfile on;

	keepalive_timeout 65;

	server {
		listen 80;
		server_name localhost;


		location / {
			root html;
			index index.html index.htm;
		}


		error_page 500 502 503 504 /50x.html;
		location = /50x.html {
			root html;
		}
	}

server {
    listen       9443 ssl;
    server_name  localhost;

    ssl_certificate      /usr/local/nginx/conf/ssl/nginx.crt;
    ssl_certificate_key  /usr/local/nginx/conf/ssl/nginx.key;

    #ssl_session_cache    shared:SSL:1m;
    #ssl_session_timeout  5m;

    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          HIGH:!aNULL:!MD5;
    #ssl_prefer_server_ciphers on;

    location / {
        root   html;
        index  index.html index.htm;
    }
}
}
EOF

sudo /usr/local/nginx/sbin/nginx -s reload
fi

sudo sed -i "s/listen 80;/listen $puerto;/" /usr/local/nginx/conf/nginx.conf
sudo sed -i "s/listen 9443 ssl;/listen $puerto_https ssl;/" /usr/local/nginx/conf/nginx.conf

if systemctl is-active --quiet nginx; then
        echo "✅ Nginx instalado y funcionando en el puerto $puerto"
        echo "🌐 Puede acceder a Nginx en: http://localhost:$puerto o http://127.0.0.1:$puerto"
        if [[ "$ssl_activate" == "si" ]]; then
            echo "🌐 Acceda mediante https://localhost:$puerto (certificado autofirmado)"
        fi
    fi
    
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



# Definir la raíz del FTP
FTP_ROOT="/srv/ftp"
export PATH=$PATH:/usr/bin


# Crear directorios FTP
echo "📂 Creando directorios FTP..."
mkdir -p "$FTP_ROOT/http/ubuntu/caddy" "$FTP_ROOT/http/ubuntu/tomcat" "$FTP_ROOT/http/ubuntu/nginx"

# Definir variables de destino para las descargas
CTARGET_DIR="$FTP_ROOT/http/ubuntu/caddy"
TARGET_DIR="$FTP_ROOT/http/ubuntu/tomcat"
NTARGET_DIR="$FTP_ROOT/http/ubuntu/nginx"

install_ftp() {
    PROFTPD_CONF="/etc/proftpd/proftpd.conf"
    TLS_CONF="/etc/proftpd/tls.conf"
    CERT_FILE="/etc/ssl/private/proftpd.pem"

    echo "📦 Instalando ProFTPD y acl..."
    apt update && apt install -y proftpd acl

    echo "⚙  Configurando ProFTPD..."
    sed -i 's/# DefaultRoot/DefaultRoot/g' "$PROFTPD_CONF"
    sed -i 's/# RequireValidShell/RequireValidShell/g' "$PROFTPD_CONF"

    echo "🚠 Habilitando modo pasivo en ProFTPD..."
    echo -e "\nPassivePorts 49152 65534" >> "$PROFTPD_CONF"

    chown -R root:root "$CTARGET_DIR"
    chmod 755 "$CTARGET_DIR"

    chown -R root:root "$TARGET_DIR"
    chmod 755 "$TARGET_DIR"

    chown -R root:root "$NTARGET_DIR"
    chmod 755 "$NTARGET_DIR"

    echo "📜 Configurando reglas de ProFTPD..."
    echo "DefaultRoot /srv/ftp/http/ubuntu" >> "$PROFTPD_CONF"

    systemctl restart proftpd

    echo "✅ FTP instalado y configurado con éxito."
}

# Función para crear usuarios sin grupos y con acceso a http/ubuntu
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

        if id "$USERNAME" &>/dev/null; then
            echo "⚠  El usuario $USERNAME ya existe, saltando creación..."
            continue
        fi

        useradd -m -s /bin/false "$USERNAME"
        usermod -d "/srv/ftp/http/ubuntu" "$USERNAME"
        chown "$USERNAME:$USERNAME" "/srv/ftp/http/ubuntu"
        chmod 755 "/srv/ftp/http/ubuntu"
        echo "$USERNAME:$PASSWORD" | chpasswd

        echo "✅ Usuario $USERNAME creado con acceso."
    done

    echo "🔄 Reiniciando ProFTPD..."
    systemctl restart proftpd

    echo "🎉 Usuarios creados con éxito."
}


connect_ftp() {
    echo "=== Conexión FTP ==="

    # Validar el servidor FTP: se repite hasta lograr conectarse
    while true; do
        read -p "Ingrese el servidor FTP (por defecto 'localhost'): " ftp_server
        ftp_server=${ftp_server:-localhost}
        # Intentar conectar y ejecutar 'quit', redirigiendo errores
        test_output=$(ftp -inv "$ftp_server" 2>&1 <<EOF
quit
EOF
)
        if echo "$test_output" | grep -qiE "(Connection refused|not known|Couldn't resolve host|timed out)"; then
            echo "❌ Error al conectar con el servidor FTP ($ftp_server). Verifique la IP/dominio e intente nuevamente."
        else
            break
        fi
    done

    # Solicitar usuario y contraseña hasta autenticarse correctamente
    while true; do
        read -p "Ingrese el usuario FTP: " ftp_user
        read -s -p "Ingrese la contraseña FTP: " ftp_pass
        echo ""
        remote_output=$(ftp -inv "$ftp_server" 2>&1 <<EOF
user $ftp_user $ftp_pass
cd /srv/ftp/http/ubuntu
quit
EOF
)
        # Si ocurre un error de conexión durante la autenticación, se vuelve a solicitar el servidor.
        if echo "$remote_output" | grep -qiE "(Connection refused|not known|Couldn't resolve host|timed out)"; then
            echo "❌ Error en la conexión al servidor FTP durante la autenticación. Verifique la IP/dominio."
            connect_ftp
            return
        fi

        if echo "$remote_output" | grep -q "230"; then
            break
        else
            echo "❌ Error de autenticación. Verifique usuario y contraseña e intente nuevamente."
        fi
    done

    # Obtener listado de carpetas en /srv/ftp/http/ubuntu
    remote_output=$(ftp -inv "$ftp_server" 2>/dev/null <<EOF
user $ftp_user $ftp_pass
cd /srv/ftp/http/ubuntu
nlist
bye
EOF
)
    # Filtrar solo líneas que sean nombres "limpios"
    mapfile -t dir_array < <(echo "$remote_output" | grep -E '^[A-Za-z0-9_-]+$')
    if [ ${#dir_array[@]} -eq 0 ]; then
        echo "No se encontraron carpetas (vía FTP)."
        return 1
    fi

    echo "Carpetas en /srv/ftp/http/ubuntu (vía FTP):"
    select service_choice in "${dir_array[@]}"; do
         if [[ -n "$service_choice" ]]; then
             echo "Ha seleccionado: $service_choice"
             break
         else
             echo "Opción inválida. Intente de nuevo."
         fi
    done

    # Obtener listado de archivos dentro de la carpeta seleccionada
    remote_files_output=$(ftp -inv "$ftp_server" 2>/dev/null <<EOF
user $ftp_user $ftp_pass
cd /$service_choice
nlist
bye
EOF
)
    mapfile -t file_array < <(echo "$remote_files_output" | grep -E '^[A-Za-z0-9_.-]+$')
    if [ ${#file_array[@]} -eq 0 ]; then
        echo "No se encontraron archivos en la carpeta $service_choice."
        return 1
    fi

    echo "Archivos en /srv/ftp/http/ubuntu/$service_choice (vía FTP):"
    select choice in "TODOS" "${file_array[@]}"; do
        if [[ -n "$choice" ]]; then

                file_choice=("$choice")
            echo "Ha seleccionado: ${file_choice[@]}"
            break
        else
            echo "Opción inválida. Intente de nuevo."
        fi
    done

    echo "📂 El archivo se descargará en: Downloads/Downloads"
dest_dir="Downloads/Downloads"
[ -d "$dest_dir" ] || mkdir -p "$dest_dir"

ftp -inv "$ftp_server" <<EOF
user $ftp_user $ftp_pass
cd /$service_choice
$(for file in "${file_choice[@]}"; do echo "get $file $dest_dir/$file"; done)
bye
EOF


    if [ $? -eq 0 ]; then
        echo "✅ Archivo transferido correctamente a $dest_dir"
    else
        echo "❌ Error en la transferencia con FTP. Verifique la conexión y permisos."
    fi
}


install_tomcat_ftp() {
    local install_dir="/opt/tomcat"
    local source_file=$(ls /home/yewdiel/Downloads/Downloads/apache-tomcat-*.zip 2>/dev/null | head -n1)
    local puerto=$1

    if [ -z "$source_file" ]; then
        echo "❌ No se encontró un archivo de Tomcat en /home/yewdiel/Downloads/Downloads"
        return 1
    fi

    if ! command -v java &>/dev/null; then
        echo "Instalando Java..."
        apt install -y default-jdk || { echo "Error al instalar Java"; exit 1; }
    fi

    ssl_activate=$(ssl_activate)
    if [[ "$ssl_activate" == "si" ]]; then
        while true; do
            read -p "Ingrese el puerto HTTPS para Tomcat (por defecto 8443): " puerto_https
            puerto_https=${puerto_https:-8443}
            if validate_https_port "$puerto_https"; then
                break
            else
                echo "❌ Puerto HTTPS inválido. Intente de nuevo."
            fi
        done
    fi

    echo "📦 Instalando Tomcat desde $source_file..."

    if [ -d "$install_dir" ]; then
        echo "Eliminando instalación anterior de Tomcat en $install_dir..."
        rm -rf "$install_dir"
    fi

    mkdir -p "$install_dir"
    unzip -q "$source_file" -d "$install_dir"

    local extracted_dir=$(find "$install_dir" -maxdepth 1 -type d -name "apache-tomcat-*" | head -n1)
    if [ -z "$extracted_dir" ]; then
        echo "❌ No se pudo detectar la carpeta de Tomcat descomprimida."
        return 1
    fi

    mv "$extracted_dir"/* "$install_dir"/
    rm -rf "$extracted_dir"

    echo "⚙ Configurando Tomcat para usar el puerto $puerto..."
    sed -i "s/port=\"8080\"/port=\"$puerto\"/" "$install_dir/conf/server.xml"
    
    if [[ "$ssl_activate" == "si" ]]; then
        sed -i "/<\/Service>/i \
        <Connector port=\"$puerto_https\" protocol=\"HTTP/1.1\" SSLEnabled=\"true\" \
        maxThreads=\"150\" scheme=\"https\" secure=\"true\" \
        clientAuth=\"false\" sslProtocol=\"TLS\" \
        keystoreFile=\"$install_dir/conf/keystore.jks\" \
        keystorePass=\"changeit\" />" "$install_dir/conf/server.xml"

        echo "SSL activado en el puerto $puerto_https."

        if [[ ! -f "$install_dir/conf/keystore.jks" ]]; then
            echo "Generando keystore autofirmado..."
            keytool -genkey -keyalg RSA -alias tomcat -keystore "$install_dir/conf/keystore.jks" \
                -storepass changeit -validity 3650 -keysize 2048 \
                -dname "CN=localhost, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=US"
        fi
    fi

    if ! id -u tomcat &>/dev/null; then
        echo "Creando usuario tomcat..."
        useradd -m -d "$install_dir" -U -s /bin/false tomcat
    fi

    chown -R tomcat:tomcat "$install_dir"
    chmod +x "$install_dir/bin/"*.sh

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
Environment="CATALINA_HOME=$install_dir"
Environment="CATALINA_BASE=$install_dir"
Environment="CATALINA_PID=$install_dir/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M"

ExecStart=$install_dir/bin/startup.sh
ExecStop=$install_dir/bin/shutdown.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tomcat
    systemctl start tomcat

    sleep 3
    if systemctl is-active --quiet tomcat; then
        echo "✅ Tomcat instalado y funcionando en el puerto $puerto"
        echo "🌐 Puedes acceder a Tomcat en: http://localhost:$puerto"
        [[ "$ssl_activate" == "si" ]] && echo "   o en: https://localhost:$puerto_https"
    else
        echo "❌ Error al iniciar Tomcat. Verifique el log:"
        tail -n 20 "$install_dir/logs/catalina.out"
        systemctl status tomcat --no-pager
    fi
}





install_caddy_ftp() {
    local install_dir="/usr/local/bin"
    local puerto=$1
    local source_files=(/home/yewdiel/Downloads/Downloads/caddy_*_linux_amd64.tar.gz)

    if [[ ! -e "${source_files[0]}" ]]; then
        echo "❌ No se encontró un archivo de Caddy en /home/yewdiel/Downloads/Downloads"
        return 1
    fi

    local source_file="${source_files[0]}"
    echo "📦 Instalando Caddy desde $source_file..."

    file_type=$(file -b "$source_file")
    if echo "$file_type" | grep -q 'gzip compressed data'; then
        tar -xzf "$source_file" -C "$install_dir"
    elif echo "$file_type" | grep -q 'Zip archive data'; then
        sudo apt install -y unzip
        unzip "$source_file" -d "$install_dir"
    else
        echo "❌ Formato de archivo no reconocido o no es comprimido con gzip."
        return 1
    fi

    if ls "$install_dir"/caddy* 1> /dev/null 2>&1; then
        mv "$install_dir"/caddy* "$install_dir/caddy"
    else
        echo "❌ No se encontró el ejecutable de Caddy tras la extracción."
        return 1
    fi

    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    sudo chmod +x "$install_dir/caddy"
    sudo chown root:root "$install_dir/caddy"

    # Otorgar permisos para usar puertos privilegiados
    sudo setcap 'cap_net_bind_service=+ep' "$install_dir/caddy"
    
    echo "✅ Caddy instalado en $install_dir"

    ssl_activate=$(ssl_activate)
    if [[ "$ssl_activate" == "si" ]]; then
        while true; do
            read -p "Ingrese el puerto HTTPS para Caddy (por defecto 443): " puerto_https
            puerto_https=${puerto_https:-443}
            if validate_https_port "$puerto_https"; then
                break
            else
                echo "❌ Puerto HTTPS inválido. Intente de nuevo."
            fi
        done
        ssl_config="    tls internal"
        sudo mkdir -p /etc/caddy/certs
        if [[ ! -f /etc/caddy/certs/caddy.key || ! -f /etc/caddy/certs/caddy.crt ]]; then
            sudo openssl req -x509 -newkey rsa:2048 -nodes \
                -keyout /etc/caddy/certs/caddy.key -out /etc/caddy/certs/caddy.crt \
                -days 365 -subj "/CN=localhost"
        fi
    else
        ssl_config=""
        puerto_https=""
    fi

    echo "⚙ Configurando Caddy para usar el puerto $puerto..."
    if [[ "$ssl_activate" == "si" ]]; then
        sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
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
        sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
http://127.0.1.1:$puerto {
    respond "Caddy funcionando en HTTP en el puerto $puerto"
}
EOF
    fi

    if ! id -u caddy >/dev/null 2>&1; then
        echo "ℹ  El usuario 'caddy' no existe. Se creará el usuario."
        sudo useradd -r -s /usr/sbin/nologin caddy
    fi

    sudo tee /etc/systemd/system/caddy.service > /dev/null << EOF
[Unit]
Description=Caddy Web Server
After=network.target

[Service]
ExecStart=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=always
User=caddy
Group=caddy
Environment="CADDYPATH=/etc/caddy"
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo chown -R caddy:caddy /etc/caddy
    sudo chmod -R 755 /etc/caddy

    sudo systemctl enable caddy
    sudo systemctl restart caddy

    sleep 3
    if systemctl is-active --quiet caddy; then
        echo "✅ Caddy instalado y funcionando en el puerto $puerto"
        echo "🌐 Acceda a Caddy en: http://localhost:$puerto o http://127.0.0.1:$puerto"
        if [[ "$ssl_activate" == "si" ]]; then
            echo "🌐 Acceda mediante HTTPS en: https://localhost:$puerto_https (certificado autofirmado)"
        fi
    else
        echo "❌ Error al iniciar Caddy. Revise el log:"
        sudo journalctl -u caddy --no-pager | tail -n 20
        systemctl status caddy --no-pager
    fi
}




install_nginx_ftp() {
    local install_dir="/usr/local/nginx"
    local source_file="/home/yewdiel/Downloads/Downloads/nginx-*.tar.gz"
    local puerto=$1

chmod 644 /home/yewdiel/Downloads/Downloads/nginx-*.tar.gz
sudo chown $USER:$USER /home/yewdiel/Downloads/Downloads/nginx-*.tar.gz

    # Verificar que exista el archivo descargado
     echo "🔍 Buscando archivo de Nginx en /home/yewdiel/Downloads/Downloads..."
ls -lh /home/yewdiel/Downloads/Downloads/nginx-*.tar.gz

local source_files=(/home/yewdiel/Downloads/Downloads/nginx-*.tar.gz)
echo "📝 Archivos encontrados: ${source_files[@]}"

if [ ${#source_files[@]} -eq 0 ]; then
    echo "❌ No se encontró el archivo de Nginx."
    return 1
fi

local source_file="${source_files[0]}"
echo "📦 Instalando Nginx desde $source_file..."

# Instalar dependencias necesarias
    sudo apt update
    sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev

    mkdir -p "$install_dir"
    tar -xzf "$source_file" -C "$install_dir" --strip-components=1
    if [ $? -ne 0 ]; then
        echo "❌ Error al extraer el archivo $source_file"
        return 1
    fi

    echo "✅ Nginx instalado en $install_dir"

# Compilar e instalar Nginx
    cd "$install_dir"
    ./configure --with-http_ssl_module
    make
    sudo make install

sudo mkdir -p /usr/local/nginx/logs
sudo touch /usr/local/nginx/logs/error.log
sudo touch /usr/local/nginx/logs/access.log
sudo chmod 644 /usr/local/nginx/logs/*.log
   
# Configurar Nginx para usar el puerto especificado
    echo "Configurando Nginx para usar el puerto $puerto..."
    sudo sed -i "s/port=\"80\"/port=\"$puerto\"/" /usr/local/nginx/conf/nginx.conf

    # Agregar /usr/local/nginx/sbin al PATH
    echo "Agregando Nginx al PATH..."

    echo 'export PATH=$PATH:/usr/local/nginx/sbin' >> ~/.bashrc
    source ~/.bashrc

    # Iniciar y habilitar el servicio
    echo "Iniciando Nginx..."
    sudo /usr/local/nginx/sbin/nginx

    # Preguntar si se desea activar SSL
    ssl_activate=$(ssl_activate)  # Se espera que esta función retorne "si" si se desea activar SSL
    if [[ "$ssl_activate" == "si" ]]; then
        while true; do
            read -p "Ingrese el puerto HTTPS para Nginx (por defecto 9443): " puerto_https
            puerto_https=${puerto_https:-9443}
            if validate_https_port "$puerto_https"; then
                break
            else
                echo "❌ Puerto HTTPS inválido. Intente de nuevo."
            fi
        done

        # Crear directorio para certificados y generar certificado autofirmado si no existe
        sudo mkdir -p /usr/local/nginx/conf/ssl
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /usr/local/nginx/conf/ssl/nginx.key -out /usr/local/nginx/conf/ssl/nginx.crt -subj "/CN=localhost"

        # Crear un archivo de configuración básico de Nginx con soporte SSL
        sudo tee /usr/local/nginx/conf/nginx.conf > /dev/null << 'EOF'
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    server {
        listen       80;
        server_name  localhost;

        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root   html;
        }
    }

    server {
        listen       9443 ssl;
        server_name  localhost;

        ssl_certificate      /usr/local/nginx/conf/ssl/nginx.crt;
        ssl_certificate_key  /usr/local/nginx/conf/ssl/nginx.key;
        ssl_protocols        TLSv1.2 TLSv1.3;
        ssl_ciphers          HIGH:!aNULL:!MD5;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }
}
EOF

        sudo /usr/local/nginx/sbin/nginx -s reload
fi

sudo sed -i "s/listen 80;/listen $puerto;/" /usr/local/nginx/conf/nginx.conf
sudo sed -i "s/listen 9443 ssl;/listen $puerto_https ssl;/" /usr/local/nginx/conf/nginx.conf

if systemctl is-active --quiet nginx; then
        echo "✅ Nginx instalado y funcionando en el puerto $puerto"
        echo "🌐 Puede acceder a Nginx en: http://localhost:$puerto o http://127.0.0.1:$puerto"
        if [[ "$ssl_activate" == "si" ]]; then
            echo "🌐 Acceda mediante https://localhost:$puerto (certificado autofirmado)"
        fi
    fi
    
}



# Tus funciones para obtener versiones y descargar instaladores se dejan tal como las tienes:
get_latest_tomcat_versions() {
    local stable_url="https://tomcat.apache.org/download-90.cgi"
    local dev_url="https://tomcat.apache.org/download-11.cgi"
    local stable_version
    local dev_version
    stable_version=$(curl -s "$stable_url" | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)
    dev_version=$(curl -s "$dev_url" | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)
    echo "$stable_version $dev_version"
}



# Obtener la última versión estable y de desarrollo de Caddy desde GitHub
get_latest_caddy_versions() {
    local stable_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    local dev_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases | grep -oP '"tag_name": "\K[^"]+' | grep beta | head -1)

    echo "$stable_version $dev_version"
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


download_tomcat_installers() {
    local target_dir="$TARGET_DIR"
    if [ -z "$target_dir" ]; then
        echo "Debes especificar el directorio de destino."
        return 1
    fi
    mkdir -p "$target_dir"
    read stable_version dev_version < <(get_latest_tomcat_versions)
    local stable_download_url="https://dlcdn.apache.org/tomcat/tomcat-9/v${stable_version}/bin/apache-tomcat-${stable_version}.zip"
    local dev_download_url="https://dlcdn.apache.org/tomcat/tomcat-11/v${dev_version}/bin/apache-tomcat-${dev_version}.zip"
    echo "Descargando Tomcat estable (v${stable_version})..."
    curl -L -o "${target_dir}/apache-tomcat-${stable_version}.zip" "$stable_download_url"
    echo "Descargando Tomcat en desarrollo (v${dev_version})..."
    curl -L -o "${target_dir}/apache-tomcat-${dev_version}.zip" "$dev_download_url"
    echo "Descargas completadas en ${target_dir}"
}

download_caddy_installers() {
    local ctarget_dir="$CTARGET_DIR"
    if [ -z "$ctarget_dir" ]; then
        echo "Debes especificar el directorio de destino."
        return 1
    fi
    mkdir -p "$ctarget_dir"
    read stable_version dev_version < <(get_latest_caddy_versions)
    # Remover la 'v' al inicio para el nombre del archivo
    local stable_version_number="${stable_version#v}"
    local dev_version_number="${dev_version#v}"
    
    local stable_download_url="https://github.com/caddyserver/caddy/releases/download/${stable_version}/caddy_${stable_version_number}_linux_amd64.tar.gz"
    local dev_download_url="https://github.com/caddyserver/caddy/releases/download/${dev_version}/caddy_${dev_version_number}_linux_amd64.tar.gz"
    
    echo "Descargando Caddy estable (${stable_version})..."
    curl -L -o "${ctarget_dir}/caddy_${stable_version_number}_linux_amd64.tar.gz" "$stable_download_url"
    
    echo "Descargando Caddy en desarrollo (${dev_version})..."
    curl -L -o "${ctarget_dir}/caddy_${dev_version_number}_linux_amd64.tar.gz" "$dev_download_url"
    
    echo "Descargas completadas en ${ctarget_dir}"
}

download_nginx_installers() {
    local ntarget_dir="$NTARGET_DIR"
    if [ -z "$ntarget_dir" ]; then
        echo "Debes especificar el directorio de destino."
        return 1
    fi
    mkdir -p "$ntarget_dir"
    read stable_version dev_version < <(get_latest_nginx_versions)
    local stable_download_url="https://nginx.org/download/nginx-${stable_version}.tar.gz"
    local dev_download_url="https://nginx.org/download/nginx-${dev_version}.tar.gz"
    echo "Descargando Nginx estable (${stable_version})..."
    curl -L -o "${ntarget_dir}/nginx-${stable_version}.tar.gz" "$stable_download_url"
    echo "Descargando Nginx en desarrollo (${dev_version})..."
    curl -L -o "${ntarget_dir}/nginx-${dev_version}.tar.gz" "$dev_download_url"
    echo "Descargas completadas en ${ntarget_dir}"
}

menu_main() { 
    while true; do
        clear
        echo "----------------------------"
        echo "Menu"
        echo "¿Por donde desea instalar su servicio: desde la web o desde FTP?"
        echo "1. Web."
        echo "2. FTP."
        echo "3. Volver al menú principal." 
        echo "============================"
        read -p "Seleccione una opción (1-3): " eleccion
        case $eleccion in
            1) menu_web ;;
            2) menu_ftpcito ;;
            3) break ;;
            *) echo "Opción no válida. Intente nuevamente." ;;
        esac
        read -p "Presione Enter para continuar..."
    done
}

menu_ftpcito() {
    while true; do
        clear
        echo "----------------------------"
        echo "Menu FTP"
        echo "1. Instalar y configurar FTP para instalar servicios web."
        echo "2. Crear usuarios para FTP."
        echo "3. Descargar instaladores y asignarlos en las carpetas."
        echo "4. Conectar FTP."
	echo "5. Instalar Caddy."
	echo "6. Instalar Tomcat."
	echo "7. Instalar Nginx."
        echo "8. Volver al menú."
        echo "============================"
        read -p "Seleccione una opción (1-8): " opcion
        case $opcion in
            1) install_ftp ;;
            2) create_users ;;
            3) 
               download_caddy_installers
               download_tomcat_installers
               download_nginx_installers ;;
            4) connect_ftp ;;
	    5)
                while true; do
                    echo "Puerto
s permitidos: 80 1024 8080 2019 3000 5000 8081"
                    read -p "Ingrese el puerto para Caddy (Enter para defecto 2019): " puerto
                    puerto=${puerto:-2019}
                    if validate_port "$puerto"; then
                        install_caddy_ftp "$puerto"
                        break
                    else
                        echo "Intente de nuevo."
                    fi
                done
                ;;
            6)
                while true; do
                    echo "Puertos permitidos: 80 1024 8080 2019 3000 5000 8081"
                    read -p "Ingrese el puerto para Tomcat (Enter para defecto 8080): " puerto
                    puerto=${puerto:-8080}
                    if validate_port "$puerto"; then
                        install_tomcat_ftp "$puerto"
                        break
                    else
                        echo "Intente de nuevo."
                    fi
                done
                ;;
            7)
                while true; do
                    echo "Puertos permitidos: 80 1024 8080 2019 3000 5000 8081"
                    read -p "Ingrese el puerto para Nginx (Enter para defecto 80): " puerto
                    puerto=${puerto:-80}
                    if validate_port "$puerto"; then
                        install_nginx_ftp "$puerto"
                        break
                    else
                        echo "Intente de nuevo."
                    fi
                done
                ;;
            8) break ;;
            *) echo "Opción no válida. Intente nuevamente." ;;
        esac
        read -p "Presione Enter para continuar..."
    done
}

menu_web() {
    while true; do
        clear
        echo "----------------------------"
        echo "Menu HTTP"
        echo "1. Instalar Caddy."
        echo "2. Instalar Tomcat."
        echo "3. Instalar Nginx."
        echo "4. Volver al menú." 
        echo "============================"
        read -p "Seleccione una opción (1-4): " choice
        case $choice in
            1)
                while true; do
                    echo "Puerto
s permitidos: 80 1024 8080 2019 3000 5000 8081"
                    read -p "Ingrese el puerto para Caddy (Enter para defecto 2019): " puerto
                    puerto=${puerto:-2019}
                    if validate_port "$puerto"; then
                        install_caddy "$puerto"
                        break
                    else
                        echo "Intente de nuevo."
                    fi
                done
                ;;
            2)
                while true; do
                    echo "Puertos permitidos: 80 1024 8080 2019 3000 5000 8081"
                    read -p "Ingrese el puerto para Tomcat (Enter para defecto 8080): " puerto
                    puerto=${puerto:-8080}
                    if validate_port "$puerto"; then
                        install_tomcat "$puerto"
                        break
                    else
                        echo "Intente de nuevo."
                    fi
                done
                ;;
            3)
                while true; do
                    echo "Puertos permitidos: 80 1024 8080 2019 3000 5000 8081"
                    read -p "Ingrese el puerto para Nginx (Enter para defecto 80): " puerto
                    puerto=${puerto:-80}
                    if validate_port "$puerto"; then
                        install_nginx "$puerto"
                        break
                    else
                        echo "Intente de nuevo."
                    fi
                done
                ;;
            4) break ;;
            *) echo "Opción no válida. Intente nuevamente." ;;
        esac
        read -p "Presione Enter para continuar..."
    done
}
menu_main
echo "Gracias por usar el script. ¡Hasta luego!"
echo "============================"
echo "Fin del script."