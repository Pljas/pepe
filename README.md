# pepe

Скрипт для автоматической установки и настройки POP Cache Node на Debian/Ubuntu.

## Быстрый старт

1. **Получите Invite Code**  
   Зарегистрируйтесь по [ссылке Airtable](https://airtable.com/apph9N7T0WlrPqnyc/pagSLmmUFNFbnKVZh/form). Код понадобится для скачивания бинарного файла.

2. **Скачайте бинарный файл**  
   Перейдите на https://download.pipe.network/, используйте invite code и скачайте архив pop-v@.3.0-Linux-x.tar.gz.

3. **Скопируйте архив на сервер**  
   Поместите скачанный архив pop-v@.3.0-Linux-x.tar.gz в домашнюю директорию пользователя на сервере.

4. **Запустите установку одной командой**  
   (скрипт скачает и выполнит последнюю версию из репозитория)

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Pljas/pepe/refs/heads/main/setup_pipe_node.sh | sudo bash
   ```

   Или скачайте скрипт вручную и запустите:
   ```sh
   wget https://raw.githubusercontent.com/Pljas/pepe/refs/heads/main/setup_pipe_node.sh
   sudo bash setup_pipe_node.sh
   ```

## Описание

- Скрипт автоматически:
  - Создаёт пользователя и директории
  - Устанавливает зависимости
  - Распаковывает архив pop-v@.3.0-Linux-x.tar.gz и переносит бинарник
  - Запрашивает параметры для config.json
  - Настраивает systemd-сервис, лимиты, logrotate
  - Даёт инструкции по открытию портов

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
- Логи: `sudo journalctl -u popcache -f -n 100`

---

**Внимание:**
- Не запускайте скрипт повторно без необходимости — он перезапишет настройки и сервис.
- Все действия выполняются на ваш страх и риск.