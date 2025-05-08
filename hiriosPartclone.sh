#!/bin/bash

# Script para clonagem de disco com partclone
# Versão 2.3 - Com tratamento de partições montadas e avisos sobre dd

# Cores para mensagens
VERMELHO='\033[0;31m'
AMARELO='\033[1;33m'
VERDE='\033[0;32m'
NC='\033[0m' # Sem cor

# Verificar se é root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${VERMELHO}Erro: Este script deve ser executado como root ou com sudo${NC}"
    exit 1
fi

# Verificar argumentos
if [ $# -ne 3 ]; then
    echo -e "${AMARELO}Uso: $0 <disco (ex: sda, mmcblk0)> <pasta_saida> <nome_imagem>${NC}"
    echo -e "${AMARELO}Exemplo: $0 mmcblk0 /backup backup_armbian${NC}"
    exit 1
fi

DISCO="$1"
PASTA_SAIDA="$2"
NOME_ARQUIVO="$3"
ARQUIVO_SAIDA="${PASTA_SAIDA}/${NOME_ARQUIVO}.img"
ARQUIVO_LOG="${PASTA_SAIDA}/${NOME_ARQUIVO}.log"

# Função para mostrar aviso do dd
aviso_dd() {
    echo -e "${AMARELO}==============================================================${NC}"
    echo -e "${VERMELHO}AVISO: Usando dd (método mais lento)${NC}"
    echo -e "${AMARELO}Esta operação será mais demorada porque:${NC}"
    echo -e "${AMARELO}$1${NC}"
    echo -e "${AMARELO}Para melhor desempenho, execute de um Live CD/USB.${NC}"
    echo -e "${AMARELO}==============================================================${NC}"
    read -p "Pressione Enter para continuar ou Ctrl+C para cancelar..."
}

# Verificar se partição está montada
esta_montada() {
    local particao="$1"
    if mount | grep -q "/dev/${particao}"; then
        return 0
    else
        return 1
    fi
}

# Tentar remontar como somente leitura
remontar_ro() {
    local particao="$1"
    echo -e "${AMARELO}  - Tentando remontar ${particao} como somente leitura...${NC}"
    if sudo mount -o remount,ro "/dev/${particao}"; then
        echo -e "${VERDE}  - Sucesso: partição agora está somente leitura${NC}"
        return 0
    else
        echo -e "${VERMELHO}  - Falha: não foi possível remontar como somente leitura${NC}"
        return 1
    fi
}

# Obter comando partclone adequado
obter_comando_partclone() {
    local particao="$1"
    local tipo_fs=$(lsblk -no FSTYPE "/dev/${particao}" 2>/dev/null)
    
    case "$tipo_fs" in
        ext2|ext3|ext4) echo "partclone.ext4" ;;
        fat16|fat32|vfat) echo "partclone.fat" ;;
        ntfs) echo "partclone.ntfs" ;;
        *) echo "partclone.dd" ;;
    esac
}

# Verificações iniciais
echo -e "${VERDE}Iniciando processo de clonagem...${NC}"
echo -e "Disco de origem: /dev/${DISCO}"
echo -e "Arquivo de destino: ${ARQUIVO_SAIDA}"
echo -e "Log detalhado: ${ARQUIVO_LOG}"

if [ ! -e "/dev/${DISCO}" ]; then
    echo -e "${VERMELHO}Erro: Disco /dev/${DISCO} não encontrado!${NC}"
    exit 1
fi

if [ ! -d "${PASTA_SAIDA}" ]; then
    echo -e "${AMARELO}Criando diretório de saída: ${PASTA_SAIDA}${NC}"
    mkdir -p "${PASTA_SAIDA}" || { echo -e "${VERMELHO}Falha ao criar diretório!${NC}"; exit 1; }
fi

# Verificar espaço disponível
TAMANHO_DISCO=$(sudo blockdev --getsize64 "/dev/${DISCO}" | awk '{printf "%.2f", $1/1024/1024/1024}')
ESPACO_LIVRE=$(df -B1G "${PASTA_SAIDA}" | awk 'NR==2 {print $4}')

if (( $(echo "${TAMANHO_DISCO} > ${ESPACO_LIVRE}" | bc -l) )); then
    echo -e "${VERMELHO}Erro: Espaço insuficiente em ${PASTA_SAIDA}${NC}"
    echo -e "${AMARELO}Necessário: ${TAMANHO_DISCO}GB, Disponível: ${ESPACO_LIVRE}GB${NC}"
    exit 1
fi

# Criar arquivo de imagem vazio
echo -e "${VERDE}Criando arquivo de imagem...${NC}"
dd if=/dev/zero of="${ARQUIVO_SAIDA}" bs=1M count=100 status=none
sync

# Copiar tabela de partições
echo -e "${VERDE}Copiando tabela de partições...${NC}"
sfdisk -d "/dev/${DISCO}" | sfdisk "${ARQUIVO_SAIDA}" >> "${ARQUIVO_LOG}" 2>&1
partprobe "${ARQUIVO_SAIDA}"

# Processar cada partição
PARTICOES=$(lsblk -lnpo NAME "/dev/${DISCO}" | grep -v "${DISCO}$" | awk '{print $1}' | sed "s|/dev/||")
TOTAL_PARTICOES=$(echo "${PARTICOES}" | wc -l)
PARTICAO_ATUAL=1

for PART in ${PARTICOES}; do
    echo -e "\n${VERDE}Processando partição ${PARTICAO_ATUAL}/${TOTAL_PARTICOES}: ${PART}${NC}"
    PARTICAO_ATUAL=$((PARTICAO_ATUAL + 1))
    
    # Verificar se está montada
    if esta_montada "${PART}"; then
        echo -e "${AMARELO}  - ATENÇÃO: Partição está montada${NC}"
        
        if ! remontar_ro "${PART}"; then
            echo -e "${VERMELHO}  - AVISO: Usando método alternativo (dd) por segurança${NC}"
        fi
    fi
    
    # Determinar comando partclone
    COMANDO_PARTCLONE=$(obter_comando_partclone "${PART}")
    echo -e "  - Usando comando: ${COMANDO_PARTCLONE}"
    
    # Se tivermos que usar dd, mostrar aviso
    if [ "${COMANDO_PARTCLONE}" == "partclone.dd" ]; then
        if esta_montada "${PART}"; then
            aviso_dd "A partição ${PART} está montada e não pôde ser remontada como somente leitura."
        else
            aviso_dd "O sistema de arquivos da partição ${PART} não é suportado pelo partclone."
        fi
    fi
    
    # Criar sistema de arquivos na imagem
    TIPO_FS=$(lsblk -no FSTYPE "/dev/${PART}")
    echo -e "  - Criando sistema de arquivos ${TIPO_FS}"
    
    case "$TIPO_FS" in
        ext2|ext3|ext4)
            mkfs.ext4 -F "${ARQUIVO_SAIDA}-${PART}" >> "${ARQUIVO_LOG}" 2>&1
            ;;
        fat16|fat32|vfat)
            mkfs.vfat -F 32 "${ARQUIVO_SAIDA}-${PART}" >> "${ARQUIVO_LOG}" 2>&1
            ;;
        ntfs)
            mkfs.ntfs -F "${ARQUIVO_SAIDA}-${PART}" >> "${ARQUIVO_LOG}" 2>&1
            ;;
        *)
            echo -e "${AMARELO}  - AVISO: Sistema de arquivos não reconhecido${NC}"
            ;;
    esac
    
    # Clonar partição
    echo -e "  - Iniciando clonagem..."
    TEMPO_INICIO=$(date +%s)
    
    if [ "${COMANDO_PARTCLONE}" == "partclone.dd" ]; then
        dd if="/dev/${PART}" of="${ARQUIVO_SAIDA}-${PART}" bs=1M status=progress >> "${ARQUIVO_LOG}" 2>&1
    else
        "${COMANDO_PARTCLONE}" -c -s "/dev/${PART}" | dd of="${ARQUIVO_SAIDA}-${PART}" bs=1M status=progress >> "${ARQUIVO_LOG}" 2>&1
    fi
    
    TEMPO_FIM=$(date +%s)
    DURACAO=$((TEMPO_FIM - TEMPO_INICIO))
    echo -e "${VERDE}  - Clonagem concluída em ${DURACAO} segundos${NC}"
    
    # Verificar integridade
    echo -e "  - Verificando integridade..."
    if [ "${COMANDO_PARTCLONE}" != "partclone.dd" ]; then
        "${COMANDO_PARTCLONE}" -v -s "${ARQUIVO_SAIDA}-${PART}" >> "${ARQUIVO_LOG}" 2>&1
    fi
done

# Consolidar imagem final
echo -e "\n${VERDE}Consolidando imagem final...${NC}"
for PART in ${PARTICOES}; do
    dd if="${ARQUIVO_SAIDA}-${PART}" of="${ARQUIVO_SAIDA}" seek=$(parted -m "/dev/${PART}" unit b print | awk -F: '{print $2}' | tr -d 'B') conv=notrunc status=none
    rm -f "${ARQUIVO_SAIDA}-${PART}"
done

# Finalização
echo -e "\n${VERDE}Clone concluído com sucesso!${NC}"
echo -e "Arquivo de imagem: ${ARQUIVO_SAIDA}"
echo -e "Tamanho final: $(du -h "${ARQUIVO_SAIDA}" | awk '{print $1}')"
echo -e "Log completo disponível em: ${ARQUIVO_LOG}"
echo -e "Horário de término: $(date)"
echo -e "${VERDE}Processo finalizado!${NC}"

exit 0
