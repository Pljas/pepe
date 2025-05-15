# POP Cache Node Installer

Скрипт для автоматической установки и настройки POP Cache Node на Debian/Ubuntu системах.

## Быстрый старт

1. **Получите Invite Code**  

   Зарегистрируйтесь по [ссылке Airtable](https://airtable.com/apph9N7T0WlrPqnyc/pagSLmmUFNFbnKVZh/form).
   Код понадобится как для скачивания бинарного файла, так и для конфигурации ноды.

2. **Скачайте бинарный файл**  

   - Перейдите на https://download.pipe.network/
   - Используйте полученный invite code
   - Скачайте архив `pop-v*.tar.gz` для вашей системы

3. **Скопируйте архив на сервер**  

   Поместите скачанный архив в домашнюю директорию на сервере:

   ```sh
   scp pop-v*.tar.gz user@your-server:~
   ```

4. **Установите ноду**  

   На сервере выполните:

   ```sh
   # Скачать актуальную версию скрипта (или обновить существующую)
   wget -O setup_pipe_node.sh https://raw.githubusercontent.com/Pljas/pepe/refs/heads/main/setup_pipe_node.sh
   
   # Запустить установку
   sudo bash setup_pipe_node.sh
   ```

   При установке вам потребуется:
   - Invite code
   - Solana адрес для получения наград
   - Данные для идентификации ноды (имя, локация, контакты)

## Описание

Скрипт автоматически:

- Создаёт пользователя и группу `popcache`
- Устанавливает необходимые зависимости (`libssl-dev`, `ca-certificates`, `jq`)
- Оптимизирует системные настройки (sysctl, лимиты файлов)
- Ищет и распаковывает архив `pop-v*.tar.gz`
- Создаёт все необходимые директории с правильными правами доступа
- Генерирует валидный `config.json` на основе введённых данных
- Настраивает и запускает systemd-сервис
- Настраивает ротацию логов

## Требования

- Debian/Ubuntu
- Права root (sudo)
- Свободное место на диске (100+ ГБ)
- Открытые порты 80 и 443

## Управление сервисом

- Проверить статус: `sudo systemctl status popcache`
- Остановить: `sudo systemctl stop popcache`
- Запустить: `sudo systemctl start popcache`
- Перезапустить: `sudo systemctl restart popcache`
- Логи через systemd: `sudo journalctl -u popcache -f -n 100`

## Просмотр логов

- В реальном времени:

  ```sh
  tail -f /opt/popcache/logs/stdout.log
  tail -f /opt/popcache/logs/stderr.log
  ```

- Через systemd:

  ```sh
  sudo journalctl -u popcache
  ```

## Мониторинг состояния и метрик

- Проверить состояние:

  ```sh
  curl http://localhost/state
  ```

- Проверить метрики:

  ```sh
  curl http://localhost/metrics
  ```

- Проверить здоровье:

  ```sh
  curl http://localhost/health
  ```

---

**Внимание:**

- Не запускайте скрипт повторно без необходимости — он перезапишет настройки и сервис.
- Все действия выполняются на ваш страх и риск.
