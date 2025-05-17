#!/bin/bash

echo "📦 Dispositivos de Armazenamento Detectados:"
echo "----------------------------------------------"
printf "%-10s %-10s %-10s %-10s %-15s %-10s %-10s %-20s\n" "DISCO" "PARTIÇÃO" "TAMANHO" "USADO" "MONTADO EM" "TIPO" "TRANSP" "MODELO"
echo "-----------------------------------------------------------------------------------------------------------------------------"

# Lista apenas discos reais (ignora loop, zram, ram, boot, rpmb, rom)
for DEV in $(lsblk -ndo NAME,TYPE | awk '$2=="disk" {print $1}' | grep -vE 'loop|ram|zram|boot|rpmb|rom'); do
    DEV_PATH="/dev/$DEV"

    # Coleta primeira partição válida do disco (ex: sda1)
    PART=$(lsblk -ln -o NAME,TYPE "/dev/$DEV" | awk '$2=="part" {print $1; exit}')
    [ -n "$PART" ] && PART_PATH="/dev/$PART" || PART_PATH="--"

    # Informações principais
    SIZE=$(lsblk -nd -o SIZE "$DEV_PATH")
    TRAN=$(udevadm info --query=property --name="$DEV_PATH" 2>/dev/null | grep ID_BUS= | cut -d= -f2)
    MODEL=$(lsblk -nd -o MODEL "$DEV_PATH")

    # Tipo de sistema de arquivos na partição
    FSTYPE=$(lsblk -no FSTYPE "$PART_PATH" 2>/dev/null | head -n1)

    # Ponto de montagem da partição (e não do disco raiz)
    MOUNTPOINT=$(lsblk -no MOUNTPOINT "$PART_PATH" 2>/dev/null | grep -vE '^$' | head -n1)

    # Espaço usado
    if [ -n "$MOUNTPOINT" ]; then
        FS_TYPE=$(df -T "$MOUNTPOINT" | awk 'NR==2 {print $2}')
        if [[ "$FS_TYPE" =~ ^(tmpfs|devtmpfs|overlay|zramfs)$ ]]; then
            USED="--"
            MOUNTPOINT="(não montado)"
        else
            USED=$(df -h "$MOUNTPOINT" | awk 'NR==2 {print $3}')
        fi
    else
        USED="--"
        MOUNTPOINT="(não montado)"
    fi

    # Substituições para valores vazios
    [ -z "$PART" ] && PART="--"
    [ -z "$TRAN" ] && TRAN="interno"
    [ -z "$FSTYPE" ] && FSTYPE="--"
    [ -z "$MODEL" ] && MODEL="--"

    printf "%-10s %-10s %-10s %-10s %-15s %-10s %-10s %-20s\n" "$DEV" "$PART" "$SIZE" "$USED" "$MOUNTPOINT" "$FSTYPE" "$TRAN" "$MODEL"
done
