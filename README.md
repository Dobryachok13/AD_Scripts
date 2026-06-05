# AD_Scripts

PowerShell скрипты для мониторинга Active Directory.

## Скрипты

- `Find-StalePasswords.ps1` — поиск пользователей с паролями старше 90 дней. Отправляет отчёт в Telegram.
- `Setup-DevOpsServer.ps1` — идемпотентная настройка Windows Server для DevOps-задач (Git, PowerShell 7, клонирование репозитория).

## CI/CD

При пуше в `main` скрипты автоматически деплоятся на сервер `DEV-OPS` через GitHub Actions.
