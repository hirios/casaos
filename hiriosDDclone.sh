#!/bin/bash

# -------- 1. Verifica dependências --------
REQUIRED_CMDS=(wget parted gzip pigz xz udevadm e2fsck)
MISSING=()

echo "🔍 Verificando dependências..."

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "⚙️ Instalando dependências ausentes: ${MISSING[*]}"
    sudo apt update
    sudo apt install -y wget parted gzip pigz xz-utils udev e2fsprogs
else
    echo "✅ Todas as dependências já estão instaladas."
fi

# -------- 2. Instala pishrink se necessário --------
if [ ! -f /usr/local/bin/pishrink.sh ]; then
    echo "📥 Baixando pishrink.sh..."
    wget -q https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O pishrink.sh
    chmod +x pishrink.sh
    sudo mv pishrink.sh /usr/local/bin/
    echo "✅ pishrink instalado em /usr/local/bin/pishrink.sh"
else
    echo "✅ pishrink já está instalado."
fi

# -------- 3. Valida argumentos --------
if [ $# -ne 2 ]; then
    echo "Uso: $0 <dispositivo> <caminho/para/saida.img ou pasta>"
    exit 1
fi

DISK="${1%/}"  # remove barra final se houver
OUTPUT_PATH="${2%/}"

if [ ! -b "$DISK" ]; then
    echo "❌ Erro: '$DISK' não é um dispositivo de bloco válido."
    exit 1
fi

# -------- 4. Define nome do arquivo de saída --------
if [ -d "$OUTPUT_PATH" ]; then
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    OUTPUT_FILE="$OUTPUT_PATH/$(basename "$DISK")_resize_$TIMESTAMP.img"
else
    OUTPUT_FILE="$OUTPUT_PATH"
fi

# -------- 5. Aviso de sobrescrita --------
if [ -f "$OUTPUT_FILE" ]; then
    echo "⚠️ Atenção: o arquivo '$OUTPUT_FILE' já existe e será sobrescrito."
    rm -f "$OUTPUT_FILE"
fi

# -------- 6. Criação da imagem --------
echo "📦 Criando imagem de '$DISK' em '$OUTPUT_FILE'..."
sudo dd if="$DISK" of="$OUTPUT_FILE" bs=4M status=progress conv=fsync

# -------- 7. Executa pishrink --------
echo "🔧 Reduzindo imagem com pishrink..."
sudo pishrink.sh "$OUTPUT_FILE"

echo "✅ Imagem final criada e reduzida com sucesso: $OUTPUT_FILE"
