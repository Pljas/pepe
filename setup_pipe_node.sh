#!/bin/bash

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
echo "1.2 Установка необходимых зависимостей (libssl-dev, ca-certificates)..."
apt update > /dev/null
apt install -y libssl-dev ca-certificates
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

# Перемещение и проверка бинарного файла
# --- Новый блок: Поиск и распаковка архива, если найден ---
echo "2.2 Поиск и подготовка бинарного файла '<span class="math-inline">BINARY\_NAME' или архива pop\-v\*\.tar\.gz\.\.\."
ARCHIVE\_PATH\=</span>(find /home /root -name "pop-v*.tar.gz" -type f -print -quit)
if [[ -n "$ARCHIVE_PATH" ]]; then
    echo "    - Найден архив: <span class="math-inline">ARCHIVE\_PATH"
TMP\_UNPACK\_DIR\="/tmp/pop\_unpack\_</span>$"
    mkdir -p "$TMP_UNPACK_DIR"
    tar -xzf "$ARCHIVE_PATH" -C "$TMP_UNPACK_DIR"
    if [[ ! -f "$TMP_UNPACK_DIR/$BINARY_NAME" ]]; then
        echo "[ОШИБКА] В архиве не найден бинарный файл '$BINARY_NAME'."
        rm -rf "$TMP_UNPACK_DIR"
        exit 1
    fi
    mv "$TMP_UNPACK_DIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось переместить бинарный файл из архива в $INSTALL_DIR."
        rm -rf "$TMP_UNPACK_DIR"
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    rm -rf "$TMP_UNPACK_DIR"
    echo "    - Бинарный файл извлечён из архива и перемещён в $INSTALL_DIR/<span class="math-inline">BINARY\_NAME\."
else
\# \-\-\- Старый блок\: Поиск готового бинарника \-\-\-
BINARY\_PATH\=</span>(find /home /root -name "$BINARY_NAME" -type f -print -quit) # Ищем в /home и /root
    if [[ -z "$BINARY_PATH" ]]; then
        echo "[ОШИБКА] Ни архив pop-v*.tar.gz, ни бинарный файл '$BINARY_NAME' не найдены в /home или /root."
        echo "Пожалуйста, скачайте архив с https://download.pipe.network/ и поместите на сервер."
        exit 1
    fi
    echo "    - Бинарный файл найден: $BINARY_PATH"
    mv "$BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
    if [ $? -ne 0 ]; then
        echo "[ОШИБКА] Не удалось переместить бинарный файл в $INSTALL_DIR."
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    echo "    - Бинарный файл перемещён в $INSTALL_DIR/<span class="math-inline">BINARY\_NAME и сделан исполняемым\."
fi
echo "\-\-\- Шаг 2 Завершен \-\-\-"
\# \-\-\- 3\. Конфигурация \-\-\-
echo ""
echo "\-\-\- Шаг 3\: Конфигурация \(config\.json\) \-\-\-"
echo "Сейчас вам нужно будет ввести данные для конфигурационного файла\."
echo "Некоторые значения имеют рекомендации\."
\# Значения по умолчанию на случай сбоя ввода
DEFAULT\_POP\_NAME\="default\-pop"
DEFAULT\_POP\_LOCATION\="Unknown"
DEFAULT\_MEMORY\_CACHE\_SIZE\_MB\=4096
DEFAULT\_DISK\_CACHE\_SIZE\_GB\=100
DEFAULT\_WORKERS\=0
DEFAULT\_NODE\_NAME\="default\-node"
DEFAULT\_IDENTITY\_NAME\="Default User"
DEFAULT\_IDENTITY\_EMAIL\="default@example\.com"
DEFAULT\_IDENTITY\_WEBSITE\=""
DEFAULT\_IDENTITY\_DISCORD\=""
DEFAULT\_IDENTITY\_TELEGRAM\=""
DEFAULT\_IDENTITY\_SOLANA\_PUBKEY\=""
while true; do
\# Запрос данных у пользователя
read \-p "Введите имя вашего POP \(pop\_name, например, my\-frankfurt\-pop\)\: " user\_pop\_name
read \-p "Введите локацию вашего POP \(pop\_location, например, Frankfurt, Germany\)\: " user\_pop\_location
\# Получаем RAM в МБ и Диск в ГБ для рекомендаций
TOTAL\_RAM\_MB\=</span>(grep MemTotal /proc/meminfo | awk '{print int(<span class="math-inline">2/1024\)\}'\)
AVAIL\_DISK\_GB\=</span>(df -BG "$INSTALL_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')

    echo "Рекомендации по памяти (RAM: ${TOTAL_RAM_MB}MB):"
    echo "  - Установите 50-70% от доступной RAM."
    echo "  - Например, для 16GB (16384MB) RAM, установите 8192-11468 MB."
    read -p "Размер кэша в памяти (memory_cache_size_mb): " user_memory_cache_size_mb

    echo "Рекомендации по диску (Доступно: ${AVAIL_DISK_GB}GB в <span class="math-inline">INSTALL\_DIR\)\:"
echo "  \- Оставьте как минимум 20% свободного места на диске\."
echo "  \- Например, для 500GB диска, установите 350\-400 GB\."
read \-p "Размер дискового кэша \(disk\_cache\_size\_gb\)\: " user\_disk\_cache\_size\_gb
read \-p "Количество воркеров \(workers, 0\=автоопределение по CPU, рекомендуется\)\: " user\_workers
user\_workers\=</span>{user_workers:-0}

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

    # Создание config.json
    echo "3.1 Создание файла конфигурации $CONFIG_FILE..."
    cat > "<span class="math-inline">CONFIG\_FILE" << EOL
\{
"pop\_name"\: "</span>{user_pop_name:-"<span class="math-inline">DEFAULT\_POP\_NAME"\}",
"pop\_location"\: "</span>{user_pop_location:-"$DEFAULT_POP_LOCATION"}",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": ${user_workers:-"$DEFAULT_WORKERS"}
  },
  "cache_config": {
    "memory_cache_size_mb": ${user_memory_cache_size_mb:-"$DEFAULT_MEMORY_CACHE_SIZE_MB"},
    "disk_cache_path": "$CACHE_DIR",
    "disk_cache_size_gb": ${user_disk_cache_size_gb:-"<span class="math-inline">DEFAULT\_DISK\_CACHE\_SIZE\_GB"\},
"default\_ttl\_seconds"\: 86400,
"respect\_origin\_headers"\: true,
"max\_cacheable\_size\_mb"\: 1024
\},
"api\_endpoints"\: \{
"base\_url"\: "https\://dataplane\.pipenetwork\.com"
\},
"identity\_config"\: \{
"node\_name"\: "</span>{user_identity_node_name:-"<span class="math-inline">DEFAULT\_NODE\_NAME"\}",
"name"\: "</span>{user_identity_name:-"<span class="math-inline">DEFAULT\_IDENTITY\_NAME"\}",
"email"\: "</span>{user_identity_email:-"<span class="math-inline">DEFAULT\_IDENTITY\_EMAIL"\}",
"website"\: "</span>{user_identity_website:-"<span class="math-inline">DEFAULT\_IDENTITY\_WEBSITE"\}",
"discord"\: "</span>{user_identity_discord:-"<span class="math-inline">DEFAULT\_IDENTITY\_DISCORD"\}",
"telegram"\: "</span>{user_identity_telegram:-"$DEFAULT_IDENTITY_TELEGRAM"}",
    "solana_pubkey": "$user_identity_solana_pubkey"
  }
}
EOL

    # Валидация конфига (если возможно)
    echo "3.2 Попытка валидации конфигурации..."
    chown $NODE_USER:$NODE_GROUP "$CONFIG_FILE"
    sudo -u $NODE_USER "$INSTALL_DIR/$BINARY_NAME" --config "$CONFIG_FILE" --validate-config
    if [ $? -ne 0 ]; then
        echo "[ПРЕДУПРЕЖДЕНИЕ] Валидация конфигурации не удалась. Проверьте $CONFIG_FILE и вывод выше."
        read -p "Повторить ввод всех параметров? (y/N): " confirm_validation
        if [[ "<span class="math-inline">confirm\_validation" \=\~ ^\[Yy\]</span> ]]; then
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
$LOG_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 $NODE_USER $NODE_GROUP