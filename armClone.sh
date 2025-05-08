#!/bin/bash

# -------- Função para listar dispositivos de bloco --------
listar_dispositivos() {
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT -d -e 7,11 | grep -E "disk" | awk '{print "/dev/"$1" ("$2")"}'
}

# -------- Função para o menu de seleção de discos --------
selecionar_dispositivo() {
    local tipo="$1" # "origem" ou "destino"
    local discos=()
    local i=1

    echo "🔍 Discos disponíveis para $tipo:"
    while IFS= read -r linha; do
        echo "  [$i] $linha"
        discos+=("$linha")
        ((i++))
    done < <(listar_dispositivos)

    while true; do
        read -rp "Digite o número correspondente ao disco $tipo: " escolha
        if [[ "$escolha" =~ ^[0-9]+$ ]] && (( escolha >= 1 && escolha <= ${#discos[@]} )); then
            echo "${discos[$((escolha-1))]}" | awk '{print $1}'
            return
        else
            echo "❌ Escolha inválida. Tente novamente."
        fi
    done
}

# -------- Função para montar partição --------
montar_particao() {
    local dispositivo="$1"
    local ponto="/mnt/hirioshd"

    if mount | grep -q "$dispositivo"; then
        ponto_montado=$(mount | grep "$dispositivo" | awk '{print $3}')
        echo "$ponto_montado"
    else
        sudo mkdir -p "$ponto"
        sudo mount "$dispositivo" "$ponto"
        echo "$ponto"
    fi
}

# -------- Verifica dependências --------
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
    sudo apt install -y "${MISSING[@]}"
else
    echo "✅ Todas as dependências já estão instaladas."
fi

# -------- Instala pishrink se necessário --------
if [ ! -f /usr/local/bin/pishrink.sh ]; then
    echo "📥 Baixando pishrink.sh..."
    wget -q https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O pishrink.sh
    chmod +x pishrink.sh
    sudo mv pishrink.sh /usr/local/bin/
    echo "✅ pishrink instalado em /usr/local/bin/pishrink.sh"
else
    echo "✅ pishrink já está instalado."
fi

# -------- Modo para leigos --------
if [[ "$1" == "--assistente" ]]; then
    DISK=$(selecionar_dispositivo "origem")

    DEST_DISK=$(selecionar_dispositivo "destino")
    DEST_PARTITION="${DEST_DISK}1"

    MOUNT_POINT=$(montar_particao "$DEST_PARTITION")

    DEST_DIR="$MOUNT_POINT/hiriosHDclone"
    sudo mkdir -p "$DEST_DIR"

    read -rp "📝 Nome do arquivo de saída (sem espaço, com ou sem .img): " NOME_ARQUIVO

    if [[ "$NOME_ARQUIVO" != *.img ]]; then
        NOME_ARQUIVO="${NOME_ARQUIVO}.img"
    fi

    OUTPUT_FILE="$DEST_DIR/$NOME_ARQUIVO"
else
    # -------- Modo avançado por linha de comando --------
    if [ $# -ne 2 ]; then
        echo "Uso: $0 <dispositivo> <caminho/para/saida.img ou pasta>"
        echo "Ou:  $0 --assistente   (modo passo-a-passo para leigos)"
        exit 1
    fi

    DISK="${1%/}"
    OUTPUT_PATH="$2"

    if [ ! -b "$DISK" ]; then
        echo "❌ Erro: '$DISK' não é um dispositivo de bloco válido."
        exit 1
    fi

    if [ -d "$OUTPUT_PATH" ]; then
        TIMESTAMP=$(date +%Y%m%d%H%M%S)
        OUTPUT_FILE="$OUTPUT_PATH/$(basename "$DISK")_resize_$TIMESTAMP.img"
    else
        OUTPUT_FILE="$OUTPUT_PATH"
    fi
fi

# -------- Aviso de sobrescrita --------
if [ -f "$OUTPUT_FILE" ]; then
    echo "⚠️ O arquivo '$OUTPUT_FILE' já existe e será sobrescrito."
    rm -f "$OUTPUT_FILE"
fi

# -------- Criação da imagem --------
echo "📦 Criando imagem de '$DISK' em '$OUTPUT_FILE'..."
sudo dd if="$DISK" of="$OUTPUT_FILE" bs=4M status=progress conv=fsync

# -------- Executa pishrink --------
echo "🔧 Reduzindo imagem com pishrink..."
sudo pishrink.sh "$OUTPUT_FILE"

echo "✅ Imagem final criada e reduzida: $OUTPUT_FILE"
