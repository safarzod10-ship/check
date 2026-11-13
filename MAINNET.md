# SOMORA — переход на mainnet (чеклист)

> ⚠️ Mainnet = **реальные деньги**. Ошибка в контракте или ключах = реальные потери.
> Перед запуском: аудит контракта и юридическая проверка (обмен крипты →
> лицензия/KYC/AML — ответственность владельца проекта).

## 0. Предусловия
- Реальный **TON** на кошельке-деплойере (≈3–5 TON на газ: деплой SOMONI,
  деплой казны, минт, настройка).
- Решить экономику: общий выпуск SOMONI, стартовый курс (SOMONI за 1 TON),
  стартовый запас в казне.
- **Бэкап** 24 слов деплойера и владельца; релизный keystore (`release/`) в
  надёжном месте.

## 1. Деплой токена SOMONI (mainnet)
Скрипт `app/scripts/deploy-somoni.mjs` сейчас настроен на testnet. Для mainnet:
- заменить endpoint на `https://toncenter.com/api/v2/jsonRPC` (ещё лучше — свой
  API-ключ, см. §5);
- запустить: `MINT_TO=<адрес-казначейства-или-владельца> SUPPLY=<выпуск> node scripts/deploy-somoni.mjs`;
- записать полученный **master-адрес** SOMONI.

## 2. Деплой казны (mainnet)
`app/contracts/somora_treasury.tact` уже скомпилирован. В `scripts/deploy-treasury.ts`:
- endpoint → mainnet; `OWNER` → твой mainnet-адрес; `SOMONI_MASTER` → из §1;
  `RATE_SOMONI_PER_TON`, `INVENTORY` → по экономике;
- запустить `npx tsx scripts/deploy-treasury.ts`;
- владельцем подписать `SetJettonWallet` (`scripts/setup-treasury-owner.ts` с
  `USER_MNEMONIC`), проверить `getInfo`.

## 3. Подключить адреса в приложение
`app/src/ton.ts`:
- `JETTONS → somoni → master.mainnet = "<master из §1>"`;
- `TREASURY.mainnet = { address, owner, rate, min }` (из §2).
Пересобрать: `npm run build && npx cap copy android`.

## 4. Проверка в сети
- Малой суммой проверить **покупку** (TON → SOMONI приходит, TON → владельцу).
- Проверить из приложения: курс, вывод TON, пополнение запаса (экран «Казначейство»).
- Отключить testnet по умолчанию (в `storage.ts` `getSettings().net`), если нужно.

## 5. Надёжность
- Свой **API-ключ toncenter** (https://toncenter.com) или собственный индексатор —
  убрать лимиты `429`. Ключ вставляется в клиент (`TonClient({ apiKey })`).

## 6. Релиз приложения
- Подписанный APK: `release/somora-release.jks` (пароль в `release/PASSWORD.txt`).
  Сборка: `./gradlew :app:assembleRelease` → `zipalign` → `apksigner sign`.
- Для Google Play: тот же keystore для всех будущих обновлений (не потеряй!).

## 7. Безопасность/право (до реальных пользователей)
- **Аудит** контрактов SOMONI и казны независимой командой.
- Юридическая модель: лицензия на обмен, KYC/AML, условия использования.
- Мониторинг казны (баланс TON/SOMONI), план пополнения запаса.
