#!/bin/bash

# Función para imprimir mensajes
function PrintMessage() {
    local mensaje=$1
    local tipo=$2
    case $tipo in
        "info")
            echo -e "\033[1;32m$mensaje\033[0m"  # Verde
            ;;
        "advertencia")
            echo -e "\033[1;33m$mensaje\033[0m"  # Amarillo
            ;;
        "error")
            echo -e "\033[1;31m$mensaje\033[0m"  # Rojo
            ;;
        *)
            echo "$mensaje"  # Normal
            ;;
    esac
}

# Función para solicitar entrada del usuario con validación
function solicitar_input() {
    local mensaje=$1
    local variable
    while true; do
        read -rp "$mensaje" variable
        if [[ -n $variable || -z $variable ]]; then
            echo "$variable"
            break
        else
            PrintMessage "Entrada no válida. Por favor, intentalo de nuevo." "error"
        fi
    done
}

# Función para leer un input de texto.
# Valida que no esté vacío, que no sea un número puro y que contenga al menos una letra.
getTextInput() {
    while true; do
        read -p "Introduce un texto: " txt
        if [[ -z "$txt" ]]; then
            echo "Error: No puedes dejarlo vacío, colega."
            continue
        fi
        # Si el input es solo dígitos, se rechaza.
        if [[ "$txt" =~ ^[0-9]+$ ]]; then
            echo "Error: El texto no puede ser un valor numérico."
            continue
        fi
        # Validación para que contenga al menos una letra (se permiten acentos).
        if ! [[ "$txt" =~ [a-zA-ZáéíóúÁÉÍÓÚñÑ] ]]; then
            echo "Error: Debe contener al menos una letra."
            continue
        fi
        break
    done
    echo "$txt"
}

# Función para leer un input numérico.
# Valida que no esté vacío, que sean solo dígitos y que se encuentre en el rango permitido (por defecto 1 a 100).
getNumberInput() {
    local MIN=1
    local MAX=99999
    while true; do
        read -p "Introduce un número (entre $MIN y $MAX): " num
        if [[ -z "$num" ]]; then
            echo "Error: No puedes dejarlo vacío, ¡vamos, que no es tan difícil!"
            continue
        fi
        # Validación: el input debe ser solo dígitos (números enteros).
        if ! [[ "$num" =~ ^[0-9]+$ ]]; then
            echo "Error: Por favor, introduce un valor numérico entero."
            continue
        fi
        # Validación del rango.
        if (( num < MIN || num > MAX )); then
            echo "Error: El número debe estar entre $MIN y $MAX."
            continue
        fi
        break
    done
    echo "$num"
}