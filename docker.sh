#!/bin/bash
set -e

function instalar_docker() {
    echo "[1/6] Instalando Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

function construir_imagen_apache() {
    echo "[2/6] Creando Dockerfile personalizado de Apache..."
    mkdir -p apache_custom/html
    cat <<EOF > apache_custom/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>¡Pagina desde imagen Apache!</title>
</head>
<body>
    <h1>Bienvenido a apache desde docker</h1>
</body>
</html>
EOF

    cat <<EOF > apache_custom/Dockerfile
FROM httpd:latest
COPY html/index.html /usr/local/apache2/htdocs/index.html
EOF

    docker build -t apache-custom apache_custom
}

function crear_contenedores() {
    echo "[3/6] Creando red Docker..."
    docker network create red_comunicacion || true

    echo "Levantando contenedor Apache..."
    docker run -d --name apache_personalizado --network red_comunicacion -p 8080:80 apache-custom

    echo "Ingrese credenciales para PostgreSQL #1:"
    read -p "Usuario: " PGUSER1
    read -p "Contraseña: " PGPASS1
    read -p "Base de datos: " PGDB1

    echo "Ingrese credenciales para PostgreSQL #2:"
    read -p "Usuario: " PGUSER2
    read -p "Contraseña: " PGPASS2
    read -p "Base de datos: " PGDB2

    echo "Levantando contenedor postgres1..."
    docker run -d \
      --name postgres1 \
      --network red_comunicacion \
      -e POSTGRES_USER=$PGUSER1 \
      -e POSTGRES_PASSWORD=$PGPASS1 \
      -e POSTGRES_DB=$PGDB1 \
      postgres

    echo "Levantando contenedor postgres2..."
    docker run -d \
      --name postgres2 \
      --network red_comunicacion \
      -e POSTGRES_USER=$PGUSER2 \
      -e POSTGRES_PASSWORD=$PGPASS2 \
      -e POSTGRES_DB=$PGDB2 \
      postgres

    echo "Esperando que los servicios arranquen..."
    sleep 20

    docker exec -it postgres1 bash -c "apt-get update && apt-get install -y postgresql-client"

    # Guardar variables globales para el menú
    echo "$PGUSER1:$PGPASS1:$PGDB1:$PGUSER2:$PGPASS2:$PGDB2" > .pg_vars
}

function cargar_vars_pg() {
    IFS=":" read PGUSER1 PGPASS1 PGDB1 PGUSER2 PGPASS2 PGDB2 < .pg_vars
}

function crear_tabla_clientes() {
    cargar_vars_pg
    docker exec -i postgres2 psql -U "$PGUSER2" -d "$PGDB2" <<EOF
CREATE TABLE IF NOT EXISTS clientes (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100),
    correo VARCHAR(100)
);
EOF
    echo "✅ Tabla 'clientes' creada correctamente."
}

function insertar_datos_clientes() {
    cargar_vars_pg
    read -p "Nombre del cliente: " nombre
    read -p "Correo del cliente: " correo
    docker exec -i postgres2 psql -U "$PGUSER2" -d "$PGDB2" <<EOF
INSERT INTO clientes(nombre, correo) VALUES ('$nombre', '$correo');
EOF
    echo "✅ Cliente insertado correctamente."
}

function mostrar_info() {
    cargar_vars_pg
    echo "[INFO] Información de PostgreSQL:"
    echo "postgres1 -> usuario: $PGUSER1 | base: $PGDB1 | pass: $PGPASS1"
    echo "postgres2 -> usuario: $PGUSER2 | base: $PGDB2 | pass: $PGPASS2"
    echo "[INFO] Contenedores activos:"
    docker ps -a
}

function menu_interactivo() {
    cargar_vars_pg
    while true; do
        echo ""
        echo "=========== MENÚ INTERACTIVO ==========="
        echo "1) Crear tabla 'clientes' en postgres2"
        echo "2) Insertar nuevo cliente en postgres2"
        echo "3) Ver registros de 'clientes'"
        echo "4) Probar conexión desde postgres1 a postgres2"
        echo "5) Crear nuevo usuario y base de datos"
        echo "6) Mostrar información de contenedores"
        echo "7) Salir"
        echo "========================================"
        read -p "Seleccione una opción [1-7]: " opcion
        echo ""

        case $opcion in
            1) crear_tabla_clientes ;;
            2) insertar_datos_clientes ;;
            3)
                docker exec -it postgres2 psql -U "$PGUSER2" -d "$PGDB2" -c "\dt"
                docker exec -it postgres2 psql -U "$PGUSER2" -d "$PGDB2" -c "SELECT * FROM clientes;"
                ;;
            4)
                echo "🔗 Conectando desde postgres1 a postgres2..."
                docker exec -it postgres1 psql -h postgres2 -U "$PGUSER2" -d "$PGDB2" -c "SELECT * FROM clientes;" && \
                echo "✅ Conexión exitosa." || echo "❌ Error de conexión."
                ;;
            5)
                read -p "Nuevo usuario: " nuevo_usuario
                read -p "Contraseña: " nueva_pass
                read -p "Nueva base de datos: " nueva_db
                docker exec -i postgres2 psql -U "$PGUSER2" -d "$PGDB2" <<EOF
CREATE USER $nuevo_usuario WITH PASSWORD '$nueva_pass';
CREATE DATABASE $nueva_db OWNER $nuevo_usuario;
GRANT ALL PRIVILEGES ON DATABASE $nueva_db TO $nuevo_usuario;
EOF
                echo "✅ Usuario y base de datos creados."
                ;;
            6) mostrar_info ;;
            7)
                echo "👋 Saliendo del menú. ¡Hasta luego!"
                break
                ;;
            *) echo "❌ Opción inválida." ;;
        esac
    done
}

# --- EJECUCIÓN DEL SCRIPT ---
instalar_docker
docker pull httpd:latest
docker pull postgres:latest
construir_imagen_apache
crear_contenedores
menu_interactivo
