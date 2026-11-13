# PAYVAND

**One World. One Connection.** — нативный Android-мессенджер (Kotlin + Jetpack Compose), созданный в Таджикистане для всего мира.

| | |
|---|---|
| Клиент | Kotlin 2.1, Jetpack Compose, Material 3, MVVM, Coroutines, Navigation Compose. Без WebView. |
| Сервер | Supabase: PostgreSQL + Row Level Security, Auth, Realtime, Storage (можно self-hosted) |
| Языки | тоҷикӣ, русский, English |
| Android | 9 (API 28) и новее |

## Структура

```
app/        Android-приложение (UI, ViewModel-и, хранение сессии, медиа, уведомления)
core/       Чистый Kotlin: модели, интерфейс PayvandApi, реализация SupabaseApi, тесты
supabase/   Схема БД (migrations), шаблоны писем, Edge Function для push
docs/       Документация
tools/      gen_strings.py — единая таблица переводов для трёх языков
```

## Документация

- [docs/SETUP.md](docs/SETUP.md) — настройка сервера (база данных, почта, push), список сервисов и их бесплатные лимиты
- [docs/BUILD.md](docs/BUILD.md) — сборка APK, собственная подпись, выпуск обновлений
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — архитектура, безопасность, звонки, переезд на свой сервер
- [docs/STATUS.md](docs/STATUS.md) — что готово и проверено, а что нет

## Быстрый старт

```bash
# 1. сервер: создать проект Supabase и применить supabase/migrations (см. docs/SETUP.md)
# 2. local.properties:
#      sdk.dir=/path/to/Android/Sdk
#      PAYVAND_SUPABASE_URL=https://xxxx.supabase.co
#      PAYVAND_SUPABASE_ANON_KEY=eyJ...            (только anon/publishable ключ!)
./gradlew :core:test          # тесты
./gradlew :app:assembleDebug  # app/build/outputs/apk/debug/app-debug.apk
```

Если адрес сервера не задан при сборке, приложение при первом запуске само спросит адрес и публичный ключ.

Файлы `server.js` и `package.json` в корне — прежнее содержимое репозитория, к PAYVAND не относятся.
