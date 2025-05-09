#!/bin/bash

# -------- Verifica se está rodando como root --------
if [ "$EUID" -ne 0 ]; then
  echo "❌ Este script precisa ser executado como root. Use: sudo $0"
  exit 1
fi

# -------- 1. Verifica dependências --------
REQUIRED_CMDS=(wget parted gzip pigz xz udevadm e2fsck)
MISSING=()

RED='\e[1;31m'
GREEN='\e[1;32m'
NC='\e[0m' # No Color

echo -e "🔍 Verificando dependências..."

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! hash "$cmd" 2>/dev/null; then
        echo -e "$cmd: ${RED}Não instalado${NC}"
        MISSING+=("$cmd")
    else
        echo -e "$cmd: ${GREEN}OK${NC}"
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "⚙️  Instalando dependências ausentes: ${MISSING[*]}"
    apt update
    apt install -y wget parted gzip pigz xz-utils udev e2fsprogs
else
    echo -e "${GREEN}✅ Todas as dependências já estão instaladas.${NC}"
fi

# -------- 2. Instala pishrink se necessário --------
if [ ! -f /usr/local/bin/pishrink.sh ]; then
    echo "📥 Baixando pishrink.sh..."
    wget -q https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O pishrink.sh
    chmod +x pishrink.sh
    mv pishrink.sh /usr/local/bin/
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
dd if="$DISK" of="$OUTPUT_FILE" bs=4M status=progress conv=fsync

# -------- 7. Executa pishrink --------
echo "🔧 Reduzindo imagem com pishrink..."
pishrink.sh "$OUTPUT_FILE"

echo "✅ Imagem final criada e reduzida com sucesso: $OUTPUT_FILE"
