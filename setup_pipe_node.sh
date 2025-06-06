#!/bin/bash
set -euo pipefail

# --- Скрипт для установки и настройки POP Cache Node ---
# Предназначен для Debian/Ubuntu систем.
# Запускать с правами root (sudo).

# --- Переменные ---
INSTALL_DIR="/opt/popcache"
LOG_DIR="$INSTALL_DIR/logs"
CACHE_DIR="$INSTALL_DIR/cache" # Путь к кэшу, как в конфиге по умолчанию
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/popcache.service"
LOGROTATE_FILE="/etc/logrotate.d/popcache"
SYSCTL_CONF="/etc/sysctl.d/99-popcache.conf"
LIMITS_CONF="/etc/security/limits.d/popcache.conf"
NODE_USER="popcache"
NODE_GROUP="popcache"
BINARY_NAME="pop" # Имя скачанного бинарного файла

# --- Проверка прав root ---
if [[ $EUID -ne 0 ]]; then
   echo "[ОШИБКА] Этот скрипт нужно запускать с правами root (используйте sudo)."
   exit 1
fi

echo "--- Начало установки POP Cache Node ---"
echo "Рекомендуемые системные требования:"
echo "  - CPU: 4+ ядер"
echo "  - RAM: 16+ ГБ"
echo "  - SSD: 100+ ГБ свободного места"
echo "  - Сеть: 1 Гбит/с +"
echo ""
read -p "Нажмите Enter для продолжения..."

# --- 1. Подготовка системы ---
echo ""
echo "--- Шаг 1: Подготовка системы ---"

# Создание пользователя и группы (если не существуют)
echo "1.1 Создание пользователя '$NODE_USER' и группы '$NODE_GROUP'..."
if ! getent group $NODE_GROUP > /dev/null; then
    groupadd $NODE_GROUP
    echo "    - Группа '$NODE_GROUP' создана."
else
    echo "    - Группа '$NODE_GROUP' уже существует."
fi

if ! id -u $NODE_USER > /dev/null 2>&1; then
    useradd -r -g $NODE_GROUP -d $INSTALL_DIR -s /sbin/nologin -c "POP Cache Node User" $NODE_USER
    echo "    - Пользователь '$NODE_USER' создан."
else
    echo "    - Пользователь '$NODE_USER' уже существует."
fi

# Установка зависимостей
echo "1.2 Установка необходимых зависимостей (libssl-dev, ca-certificates, jq)..."
apt update > /dev/null
apt install -y libssl-dev ca-certificates jq
if [ $? -ne 0 ]; then
    echo "[ОШИБКА] Не удалось установить зависимости. Проверьте вывод apt."
    exit 1
fi
echo "    - Зависимости установлены."

# Оптимизация настроек сети (sysctl)
echo "1.3 Оптимизация настроек сети (sysctl)..."
cat > "$SYSCTL_CONF" << EOL
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOL
sysctl -p "$SYSCTL_CONF" > /dev/null
echo "    - Сетевые параметры ядра обновлены."

# Увеличение лимитов на файлы
echo "1.4 Увеличение лимитов на открытые файлы..."
cat > "$LIMITS_CONF" << EOL
* hard nofile 65535
* soft nofile 65535
$NODE_USER hard nofile 65535
$NODE_USER soft nofile 65535
EOL
echo "    - Лимиты настроены в $LIMITS_CONF."
echo "    - Примечание: Для сессий пользователя изменения вступят в силу после перезахода."
echo "    - Для systemd сервиса лимиты будут установлены в его конфигурации."

echo "--- Шаг 1 Завершен ---"

# --- 2. Установка ---
echo ""
echo "--- Шаг 2: Установка ---"

# Создание директорий
echo "2.1 Создание директорий ($INSTALL_DIR, $LOG_DIR, $CACHE_DIR)..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CACHE_DIR"
echo "    - Директории созданы."

# Проверка свободного места перед созданием кэша (20% свободно)
AVAIL_DISK_PERCENT=$(df --output=pcent "$INSTALL_DIR" | tail -1 | tr -dc '0-9')
if [ "$AVAIL_DISK_PERCENT" -ge 80 ]; then
    echo "[ОШИБКА] На диске недостаточно свободного места для кэша (менее 20% свободно)."
    exit 1
fi

# Перемещение и проверка бинарного файла
# --- Новый блок: Поиск и распаковка архива, если найден ---
echo "2.2 Поиск и подготовка бинарного файла '$BINARY_NAME' или архива pop-v*.tar.gz..."
# Ищем архив без учёта регистра и архитектуры
ARCHIVE_PATH=$(find /home /root -iname "pop-v*.tar.gz" -type f -print -quit)
if [[ -n "$ARCHIVE_PATH" ]]; then
    echo "    - Найден архив: $ARCHIVE_PATH"
    TMP_UNPACK_DIR="/tmp/pop_unpack_$$"
    mkdir -p "$TMP_UNPACK_DIR"
    tar -xzf "$ARCHIVE_PATH" -C "$TMP_UNPACK_DIR"
    if [[ ! -f "$TMP_UNPACK_DIR/$BINARY_NAME" ]]; then
        # Попробуем найти бинарник внутри архива по имени pop*
        BIN_FOUND=$(find "$TMP_UNPACK_DIR" -type f -name "pop*")
        if [[ -n "$BIN_FOUND" ]]; then
            mv -f "$BIN_FOUND" "$INSTALL_DIR/$BINARY_NAME"
        else
            echo "[ОШИБКА] В архиве не найден бинарный файл '$BINARY_NAME'."
            rm -rf "$TMP_UNPACK_DIR"
            exit 1
        fi
    else
        mv -f "$TMP_UNPACK_DIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    fi
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось переместить бинарный файл из архива в $INSTALL_DIR."
        rm -rf "$TMP_UNPACK_DIR"
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    # Добавляем capability для привилегированных портов (80, 443)
    if ! command -v setcap >/dev/null 2>&1; then
        echo "    - Утилита setcap не найдена, устанавливаем..."
        apt update > /dev/null
        apt install -y libcap2-bin
        if [ $? -ne 0 ]; then
            echo "[ОШИБКА] Не удалось установить libcap2-bin для setcap."
            exit 1
        fi
    fi
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/$BINARY_NAME"
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось установить capability cap_net_bind_service для $INSTALL_DIR/$BINARY_NAME."
        echo "        Приложение не сможет слушать порты 80/443 без root."
        exit 1
    else
        echo "    - Capability cap_net_bind_service успешно установлена для $INSTALL_DIR/$BINARY_NAME."
    fi
    rm -rf "$TMP_UNPACK_DIR"
    echo "    - Бинарный файл извлечён из архива и перемещён в $INSTALL_DIR/$BINARY_NAME."
else
    # --- Старый блок: Поиск готового бинарника ---
    BINARY_PATH=$(find /home /root -name "$BINARY_NAME" -type f -print -quit)
    if [[ -z "$BINARY_PATH" ]]; then
        echo "[ОШИБКА] Ни архив pop-v*.tar.gz, ни бинарный файл '$BINARY_NAME' не найдены в /home или /root."
        echo "Пожалуйста, скачайте архив с https://download.pipe.network/ и поместите на сервер."
        exit 1
    fi
    echo "    - Бинарный файл найден: $BINARY_PATH"
    mv -f "$BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось переместить бинарный файл в $INSTALL_DIR."
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    # Добавляем capability для привилегированных портов (80, 443)
    if ! command -v setcap >/dev/null 2>&1; then
        echo "    - Утилита setcap не найдена, устанавливаем..."
        apt update > /dev/null
        apt install -y libcap2-bin
        if [ $? -ne 0 ]; then
            echo "[ОШИБКА] Не удалось установить libcap2-bin для setcap."
            exit 1
        fi
    fi
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/$BINARY_NAME"
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось установить capability cap_net_bind_service для $INSTALL_DIR/$BINARY_NAME."
        echo "        Приложение не сможет слушать порты 80/443 без root."
        exit 1
    else
        echo "    - Capability cap_net_bind_service успешно установлена для $INSTALL_DIR/$BINARY_NAME."
    fi
    echo "    - Бинарный файл перемещён в $INSTALL_DIR/$BINARY_NAME и сделан исполняемым."
fi

echo "--- Шаг 2 Завершен ---"

# --- 3. Конфигурация ---
echo ""
echo "--- Шаг 3: Конфигурация (config.json) ---"
echo "Сейчас вам нужно будет ввести данные для конфигурационного файла."
echo "Некоторые значения имеют рекомендации."
# Значения по умолчанию на случай сбоя ввода
DEFAULT_POP_NAME="your-pop-name"
DEFAULT_POP_LOCATION="Your Location, Country"
DEFAULT_INVITE_CODE="Enter your Invite Code"
DEFAULT_MEMORY_CACHE_SIZE_MB=4096
DEFAULT_DISK_CACHE_SIZE_GB=100
DEFAULT_WORKERS=40
DEFAULT_NODE_NAME="your-node-name"
DEFAULT_IDENTITY_NAME="Your Name"
DEFAULT_IDENTITY_EMAIL="your.email@example.com"
DEFAULT_IDENTITY_WEBSITE=""
DEFAULT_IDENTITY_DISCORD=""
DEFAULT_IDENTITY_TELEGRAM=""
DEFAULT_IDENTITY_SOLANA_PUBKEY="YOUR_SOLANA_WALLET_ADDRESS_FOR_REWARDS"
while true; do
# Запрос данных у пользователя
read -p "Введите имя вашего POP (pop_name, например, my-frankfurt-pop): " user_pop_name
read -p "Введите локацию вашего POP (pop_location, например, Frankfurt, Germany): " user_pop_location

while true; do
    read -p "Введите ваш invite code (ОБЯЗАТЕЛЬНО): " user_invite_code
    if [[ -z "$user_invite_code" ]]; then
        echo "   [ОШИБКА] Invite code обязателен. Получите его на https://airtable.com/apph9N7T0WlrPqnyc/pagSLmmUFNFbnKVZh/form"
    else
        break
    fi
done

# Получаем RAM в МБ и Диск в ГБ для рекомендаций
TOTAL_RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
AVAIL_DISK_GB=$(df -BG "$INSTALL_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')

    echo "Рекомендации по памяти (Доступно RAM: ${TOTAL_RAM_MB}MB):"
    echo "  - Установите 50-70% от доступной RAM."
    echo "  - Например, для 16GB (16384MB) RAM, установите 8192-11468 MB."
    read -p "Размер кэша в памяти (memory_cache_size_mb). Укажите число: " user_memory_cache_size_mb

    echo "Рекомендации по диску (Доступно: ${AVAIL_DISK_GB}GB в $INSTALL_DIR):"
    echo "  - Оставьте как минимум 20% свободного места на диске."
    echo "  - Например, для 500GB диска, установите 350-400 GB."
    read -p "Размер дискового кэша (disk_cache_size_gb). Укажите число: " user_disk_cache_size_gb
    read -p "Количество воркеров (workers, 0=автоопределение по CPU, рекомендуется): " user_workers
    user_workers=${user_workers:-0}

    read -p "Имя узла для идентификации (identity_config.node_name): " user_identity_node_name
    read -p "Ваше имя или название компании (identity_config.name): " user_identity_name
    read -p "Ваш контактный email (identity_config.email): " user_identity_email
    read -p "Ваш вебсайт (identity_config.website, можно оставить пустым): " user_identity_website
    read -p "Ваш Discord username (identity_config.discord, можно оставить пустым): " user_identity_discord
    read -p "Ваш Telegram handle (identity_config.telegram, можно оставить пустым): " user_identity_telegram
    while true; do
        read -p "Ваш Solana адрес для наград (identity_config.solana_pubkey, ОБЯЗАТЕЛЬНО): " user_identity_solana_pubkey
        if [[ -z "$user_identity_solana_pubkey" ]]; then
            echo "   [ОШИБКА] Solana адрес обязателен для получения наград."
        else
            break
        fi
    done

    # Исправление генерации config.json
    # Проверяем и устанавливаем значения по умолчанию, если пусто
    : "${user_pop_name:=$DEFAULT_POP_NAME}"
    : "${user_pop_location:=$DEFAULT_POP_LOCATION}"
    : "${user_invite_code:=$DEFAULT_INVITE_CODE}"
    : "${user_memory_cache_size_mb:=$DEFAULT_MEMORY_CACHE_SIZE_MB}"
    : "${user_disk_cache_size_gb:=$DEFAULT_DISK_CACHE_SIZE_GB}"
    : "${user_workers:=$DEFAULT_WORKERS}"
    : "${user_identity_node_name:=$DEFAULT_NODE_NAME}"
    : "${user_identity_name:=$DEFAULT_IDENTITY_NAME}"
    : "${user_identity_email:=$DEFAULT_IDENTITY_EMAIL}"
    : "${user_identity_website:=$DEFAULT_IDENTITY_WEBSITE}"
    : "${user_identity_discord:=$DEFAULT_IDENTITY_DISCORD}"
    : "${user_identity_telegram:=$DEFAULT_IDENTITY_TELEGRAM}"
    : "${user_identity_solana_pubkey:=$DEFAULT_IDENTITY_SOLANA_PUBKEY}"

    echo "3.1 Создание файла конфигурации $CONFIG_FILE..."
    
    # Создаем временный файл для JSON
    TMP_CONFIG="/tmp/config.json.$$"
    
    # Генерируем JSON напрямую, без промежуточных команд
    cat > "$TMP_CONFIG" << EOF
{
  "pop_name": "$user_pop_name",
  "pop_location": "$user_pop_location",
  "invite_code": "$user_invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": $user_workers
  },
  "cache_config": {
    "memory_cache_size_mb": $user_memory_cache_size_mb,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $user_disk_cache_size_gb,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$user_identity_node_name",
    "name": "$user_identity_name",
    "email": "$user_identity_email",
    "website": "$user_identity_website",
    "discord": "$user_identity_discord",
    "telegram": "$user_identity_telegram",
    "solana_pubkey": "$user_identity_solana_pubkey"
  }
}
EOF

    # Проверяем, что временный файл создан успешно
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось создать временный файл конфигурации."
        exit 1
    fi

    # Проверяем валидность JSON перед копированием
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty "$TMP_CONFIG" 2>/dev/null; then
            echo "[ОШИБКА] Сгенерированный JSON невалиден. Проверьте входные данные."
            cat "$TMP_CONFIG"
            rm -f "$TMP_CONFIG"
            exit 1
        fi
    else
        echo "[ПРЕДУПРЕЖДЕНИЕ] jq не установлен, пропускаем валидацию JSON."
    fi

    # Копируем временный файл в целевой с нужными правами
    mv "$TMP_CONFIG" "$CONFIG_FILE"
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось переместить конфигурацию в $CONFIG_FILE"
        rm -f "$TMP_CONFIG"
        exit 1
    fi

    # Валидация конфига (если возможно)
    echo "3.2 Попытка валидации конфигурации..."
    # Создаем директории и устанавливаем права
    echo "    - Проверка и установка прав доступа..."
    mkdir -p "$CACHE_DIR"
    chown -R $NODE_USER:$NODE_GROUP "$INSTALL_DIR" "$CACHE_DIR" "$LOG_DIR"
    chmod -R 750 "$INSTALL_DIR" "$CACHE_DIR" "$LOG_DIR"
    chmod 640 "$CONFIG_FILE"
    chmod 750 "$INSTALL_DIR/$BINARY_NAME"

    echo "    - Все права доступа установлены"

    # Теперь запускаем валидацию
    sudo -u $NODE_USER sh -c 'cd "$INSTALL_DIR" && ./"$BINARY_NAME" --config "$CONFIG_FILE" --validate-config'
    if [ $? -ne 0 ]; then
        echo "[ПРЕДУПРЕЖДЕНИЕ] Валидация конфигурации не удалась. Проверьте $CONFIG_FILE и вывод выше."
        read -p "Повторить ввод всех параметров? (y/N): " confirm_validation
        if [[ "$confirm_validation" =~ ^[Yy]$ ]]; then
            continue
        else
            echo "Установка прервана для исправления конфигурации."
            exit 1
        fi
    else
        echo "    - Конфигурация успешно прошла валидацию."
        break
    fi

done

echo "--- Шаг 3 Завершен ---"

# --- 4. Настройка прав и Systemd сервиса ---
echo ""
echo "--- Шаг 4: Настройка прав и Systemd сервиса ---"

# Установка прав на директорию установки
echo "4.1 Установка прав доступа для '$NODE_USER:$NODE_GROUP' на $INSTALL_DIR..."
chown -R $NODE_USER:$NODE_GROUP "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR" # Даем права только владельцу и группе
chmod 640 "$CONFIG_FILE" # Права на чтение конфига
# Права на исполнение бинарника уже установлены ранее
echo "    - Права доступа установлены."

# Создание Systemd сервиса
echo "4.2 Создание файла systemd сервиса ($SERVICE_FILE)..."
cat > "$SERVICE_FILE" << EOL
[Unit]
Description=POP Cache Node Service
After=network.target

[Service]
Type=simple
User=$NODE_USER
Group=$NODE_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME --config $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:$LOG_DIR/stdout.log
StandardError=append:$LOG_DIR/stderr.log

[Install]
WantedBy=multi-user.target
EOL
echo "    - Файл сервиса создан."

# Перезагрузка конфигурации systemd, включение и запуск сервиса
echo "4.3 Перезагрузка systemd, включение и запуск сервиса 'popcache'..."
systemctl daemon-reload
systemctl enable popcache
systemctl start popcache
echo "    - Сервис включен и запущен."

# Проверка статуса сервиса
echo "4.4 Проверка статуса сервиса 'popcache'..."
# Даем сервису немного времени на запуск перед проверкой статуса
sleep 3
systemctl status popcache --no-pager -l # -l показывает полные строки логов
echo "    - Проверьте статус выше. 'Active: active (running)' означает успешный запуск."

echo "--- Шаг 4 Завершен ---"

# --- 5. Настройка Log Rotation ---
echo ""
echo "--- Шаг 5: Настройка ротации логов ---"

echo "5.1 Создание файла конфигурации logrotate ($LOGROTATE_FILE)..."
cat > "$LOGROTATE_FILE" << EOL
${INSTALL_DIR}/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    dateext
    maxsize 100M
    su ${NODE_USER} ${NODE_GROUP}
    create 0640 ${NODE_USER} ${NODE_GROUP}
    sharedscripts
    postrotate
        systemctl reload popcache >/dev/null 2>&1 || true
    endscript
}
EOL