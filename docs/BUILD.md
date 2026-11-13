# Сборка, подпись и обновления

## Требования
JDK 17+, Android SDK (platform 35, build-tools 35). Gradle скачивается обёрткой `./gradlew`.

## Параметры сборки
Задаются в `local.properties` (не попадает в git) или переменными окружения:

| Параметр | Назначение |
|---|---|
| `PAYVAND_SUPABASE_URL`, `PAYVAND_SUPABASE_ANON_KEY` | сервер по умолчанию. Если пусто — приложение спросит при первом запуске |
| `PAYVAND_FCM_*` | push-уведомления (docs/SETUP.md, раздел 3) |
| `PAYVAND_VERSION_CODE` | номер сборки; каждое обновление должно иметь больший номер |

`versionName` меняется в `app/build.gradle.kts`.

## Команды
```bash
./gradlew :core:test            # тесты
./gradlew :app:assembleDebug    # отладочный APK (пакет tj.payvand.app.debug, разрешён http для локального сервера)
./gradlew :app:assembleRelease  # релизный APK: R8, только HTTPS → app/build/outputs/apk/release/app-release.apk
```

## Собственная подпись релиза

Android принимает обновление, только если оно подписано **тем же ключом**, что и установленная версия.
Потеряете ключ — выпустить обновление поверх старой версии будет невозможно.

1. Создайте ключ (один раз, на своём компьютере):
   ```bash
   keytool -genkeypair -keystore payvand-release.jks -storetype PKCS12 -alias payvand \
     -keyalg RSA -keysize 4096 -validity 10000
   ```
2. Рядом с `settings.gradle.kts` создайте `keystore.properties` (он и `*.jks` уже в `.gitignore`):
   ```properties
   PAYVAND_KEYSTORE_FILE=/absolute/path/payvand-release.jks
   PAYVAND_KEYSTORE_PASSWORD=...
   PAYVAND_KEY_ALIAS=payvand
   PAYVAND_KEY_PASSWORD=...
   ```
3. `./gradlew :app:assembleRelease`. Проверка подписи:
   `apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk`

Правила: ключ и пароли не коммитятся и не пересылаются в открытых чатах; храните минимум две копии
(например, менеджер паролей и офлайн-носитель). Без `keystore.properties` релизная сборка получится неподписанной —
чужой или отладочный сертификат не подставляется.

## Сборка без компьютера (GitHub Actions)

`.github/workflows/android.yml` собирает APK при каждом push в `main`, по тегу `v*` и вручную (Actions → Run workflow).
В Settings → Secrets and variables → Actions добавьте: `PAYVAND_SUPABASE_URL`, `PAYVAND_SUPABASE_ANON_KEY`,
`PAYVAND_KEYSTORE_BASE64` (`base64 -w0 payvand-release.jks`), `PAYVAND_KEYSTORE_PASSWORD`, `PAYVAND_KEY_ALIAS`,
`PAYVAND_KEY_PASSWORD`, при необходимости `PAYVAND_FCM_*`. Готовый APK — в артефактах запуска.

## Как выпускать обновление

1. Внести изменения, поднять `versionName`; `versionCode` в CI растёт сам.
2. Если менялась база — добавить **новый** файл в `supabase/migrations/` (старые не править) и применить его
   к серверу до выхода приложения. Изменения схемы делайте обратно совместимыми: старые версии приложения
   какое-то время продолжают работать.
3. Собрать релиз тем же ключом, установить поверх старой версии на тестовом телефоне, проверить вход и переписку.
4. Раздать APK. Пользователь устанавливает его поверх — данные и вход сохраняются.

Для Google Play понадобятся: AAB (`./gradlew :app:bundleRelease`), актуальный `targetSdk` (сейчас 35 — Play может
требовать новее), политика конфиденциальности и разовый взнос 25 $ за аккаунт разработчика.
