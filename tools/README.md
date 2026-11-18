# tools — прикладные утилиты

Здесь лежит не библиотека навыков, а **готовый код**, который этими навыками проверялся. Каждый инструмент — с тестами и с честным описанием того, от чего он защищает, а от чего нет.

## kit-secret

Парольная защита ключей VPN на флешке: `vpn\config.json` и `vpn\sub.txt` превращаются в `.enc`, открытый текст на носитель не пишется.

- **Модель угроз:** чужая машина (учебный класс, общая машина), а не только потеря флешки.
- **Криптография:** PBKDF2-HMAC-SHA256 (600 000 итераций) → AES-256-CBC + HMAC-SHA256, Encrypt-then-MAC, AAD на заголовок, три разделённых ключа.
- **Совместимость:** Windows PowerShell 5.1 и PowerShell 7+.
- **Документация:** [kit-secret/README.md](kit-secret/README.md) — модель угроз, формат контейнера, использование.
- **Отчёт об изменениях:** [kit-secret/CHANGES.md](kit-secret/CHANGES.md) — что именно исправлено и где.
- **Тесты:** [kit-secret/tests/test-kit-secret.ps1](kit-secret/tests/test-kit-secret.ps1) — 33 проверки с эталонами из независимой реализации.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\kit-secret\tests\test-kit-secret.ps1
```

## Как это связано с навыками

Разбор и правка велись по навыкам из `agent-skills/`:

| Навык | Что дал |
| --- | --- |
| `crypto-engineering/zeroize-audit` | зануление ключей и открытого текста в памяти |
| `crypto-engineering/sharp-edges` | fail-open Enter, шифрование пустым паролем, отсутствие проверок в API |
| `security-crypto/cryptographic-file-format-design` | AAD на заголовок, версионирование контейнера |
| `security-crypto/secure-key-derivation-and-management` | разделение доменов ключей, параметры PBKDF2 |
| `security-crypto/applied-cryptography-engineering` | выбор режима, обоснование CBC против GCM |
| `crypto-engineering/implementing-aes-encryption-for-data-at-rest` | требования к IV/nonce и аутентификации |
