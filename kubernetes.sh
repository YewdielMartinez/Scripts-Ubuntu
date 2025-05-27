#!/bin/bash
set -e

# Variables por defecto
APP_NAME="flask-api"
IMAGE_NAME="flask-k8s"
CONTAINER_PORT=5000
SERVICE_PORT=80
CONFIG_KEY="MENSAJE"
CONFIG_VALUE="Hola desde ConfigMap"
SECRET_KEY="DB_PASSWORD"
SECRET_VALUE="supersecreto"
PV_PATH="/data/flask"
VOLUME_SIZE="1Gi"
REPLICAS=2
WORKDIR="flask-app"

function leer_input() {
    read -p "$1 [$2]: " valor
    echo "${valor:-$2}"
}

function configurar_variables() {
    echo "=== Personalizar parámetros ==="
    APP_NAME=$(leer_input "Nombre del Deployment" "$APP_NAME")
    IMAGE_NAME=$(leer_input "Nombre de la imagen Docker" "$IMAGE_NAME")
    CONTAINER_PORT=$(leer_input "Puerto que escucha Flask" "$CONTAINER_PORT")
    SERVICE_PORT=$(leer_input "Puerto del servicio (externo)" "$SERVICE_PORT")
    CONFIG_KEY=$(leer_input "Nombre de variable en ConfigMap" "$CONFIG_KEY")
    CONFIG_VALUE=$(leer_input "Valor de ConfigMap" "$CONFIG_VALUE")
    SECRET_KEY=$(leer_input "Nombre de secreto" "$SECRET_KEY")
    SECRET_VALUE=$(leer_input "Valor del secreto (sin codificar)" "$SECRET_VALUE")
    PV_PATH=$(leer_input "Ruta del volumen persistente (hostPath)" "$PV_PATH")
    VOLUME_SIZE=$(leer_input "Tamaño del volumen persistente" "$VOLUME_SIZE")
    REPLICAS=$(leer_input "Cantidad de réplicas" "$REPLICAS")
    WORKDIR=$(leer_input "Nombre del directorio de trabajo" "$WORKDIR")
}

function instalar_dependencias() {
    echo "==== Verificando herramientas necesarias ===="
    if ! command -v minikube &> /dev/null; then
        echo "Instalando Minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
    fi

    if ! command -v kubectl &> /dev/null; then
        echo "Instalando kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
}

function iniciar_minikube() {
    echo "==== Iniciando Minikube ===="
    minikube start --driver=docker
    eval $(minikube docker-env)
}

function crear_app_flask() {
    echo "==== Creando aplicación Flask en $WORKDIR ===="
    mkdir -p "$WORKDIR" && cd "$WORKDIR"

    cat > app.py <<EOF
from flask import Flask
import os
app = Flask(__name__)

@app.route("/")
def hello():
    return f"{os.getenv('$CONFIG_KEY', 'Valor no definido')}"
EOF

    cat > Dockerfile <<EOF
FROM python:3.9-slim
WORKDIR /app
COPY app.py .
RUN pip install flask
EXPOSE $CONTAINER_PORT
CMD ["python", "app.py"]
EOF

    echo "==== Construyendo imagen Docker ===="
    docker build -t "$IMAGE_NAME" .
}

function crear_manifiestos_k8s() {
    echo "==== Creando manifiestos YAML ===="

    echo "$CONFIG_VALUE" > .config_tmp && CONFIG_VALUE_BASE64=$(cat .config_tmp)
    echo "$SECRET_VALUE" | base64 > .secret_tmp && SECRET_VALUE_B64=$(cat .secret_tmp)
    rm -f .config_tmp .secret_tmp

    cat > configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-config
data:
  $CONFIG_KEY: "$CONFIG_VALUE"
EOF

    cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${APP_NAME}-secret
type: Opaque
data:
  $SECRET_KEY: $(echo -n "$SECRET_VALUE" | base64)
EOF

    cat > pv.yaml <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${APP_NAME}-pv
spec:
  capacity:
    storage: $VOLUME_SIZE
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "$PV_PATH"
EOF

    cat > pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP_NAME}-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $VOLUME_SIZE
EOF

    cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: flask
        image: $IMAGE_NAME
        ports:
        - containerPort: $CONTAINER_PORT
        env:
        - name: $CONFIG_KEY
          valueFrom:
            configMapKeyRef:
              name: ${APP_NAME}-config
              key: $CONFIG_KEY
        - name: $SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: ${APP_NAME}-secret
              key: $SECRET_KEY
        volumeMounts:
        - name: data-vol
          mountPath: /app/data
      volumes:
      - name: data-vol
        persistentVolumeClaim:
          claimName: ${APP_NAME}-pvc
EOF

    cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-svc
spec:
  selector:
    app: $APP_NAME
  ports:
    - protocol: TCP
      port: $SERVICE_PORT
      targetPort: $CONTAINER_PORT
  type: NodePort
EOF
}

function aplicar_recursos() {
    echo "==== Aplicando recursos ===="
    kubectl apply -f configmap.yaml
    kubectl apply -f secret.yaml
    kubectl apply -f pv.yaml
    kubectl apply -f pvc.yaml
    kubectl apply -f deployment.yaml
    kubectl apply -f service.yaml
    kubectl rollout status deployment/$APP_NAME
}

function ver_logs() {
    kubectl get pods -l app=$APP_NAME
    echo "Mostrando logs del primer pod:"
    pod=$(kubectl get pods -l app=$APP_NAME -o jsonpath="{.items[0].metadata.name}")
    kubectl logs "$pod"
}

function exponer_servicio() {
    echo "Accede a la aplicación con:"
    minikube service ${APP_NAME}-svc --url
}

function menu() {
    while true; do
        echo ""
        echo "========= MENÚ PRINCIPAL ========="
        echo "1. Configurar parámetros"
        echo "2. Instalar dependencias"
        echo "3. Iniciar Minikube"
        echo "4. Crear aplicación Flask"
        echo "5. Crear manifiestos YAML"
        echo "6. Aplicar recursos a Kubernetes"
        echo "7. Ver logs de la app"
        echo "8. Acceder al servicio"
        echo "9. Salir"
        echo "=================================="
        read -p "Selecciona una opción [1-9]: " opcion

        case $opcion in
            1) configurar_variables ;;
            2) instalar_dependencias ;;
            3) iniciar_minikube ;;
            4) crear_app_flask ;;
            5) crear_manifiestos_k8s ;;
            6) aplicar_recursos ;;
            7) ver_logs ;;
            8) exponer_servicio ;;
            9) echo "Saliendo..."; exit 0 ;;
            *) echo "Opción inválida" ;;
        esac
    done
}

menu
