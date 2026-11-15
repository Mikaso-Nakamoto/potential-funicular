# Agent Security & Cryptography Skills Vault

Универсальная библиотека инженерных навыков по кибербезопасности, прикладной криптографии, безопасной архитектуре и разработке собственных зашифрованных форматов данных для AI-агентов (Antigravity, Claude Code, Cursor, Codex, Windsurf и др.).

---

## Каталог навыков

### 1. [`cryptographic-file-format-design/`](cryptographic-file-format-design/SKILL.md)
**Проектирование собственного защищенного формата контейнеров и файлов:**
- Бинарная разметка заголовка (Magic Bytes, версии, идентификаторы шифров).
- Привязка всего незашифрованного заголовка к тегу аутентификации через AAD (Authenticated Additional Data).
- Потоковое шифрование фиксированными чанками (64 KB) для файлов любого объема.
- Защита от атак усечения (truncation attacks) и перестановки блоков через инкрементные nonce и маркер финального блока.

### 2. [`secure-key-derivation-and-management/`](secure-key-derivation-and-management/SKILL.md)
**Безопасная деривация, иерархия и уничтожение ключей:**
- Деривация из паролей: параметры Argon2id (RFC 9106), устойчивость к GPU/ASIC перебору.
- Разделение криптографических контекстов через HKDF (RFC 5869) `info`.
- Иерархия ключей (Envelope Encryption): Master Key → KEK → DEK для мгновенной смены пароля без перезаписи терабайтов данных.
- Защита ОЗУ: блокировка вытеснения в файл подкачки (`mlock` / `VirtualLock`), гарантированное стирание ключей (`explicit_bzero` / `SecureZeroMemory`), `constant-time` сравнение.

### 3. [`applied-cryptography-engineering/`](applied-cryptography-engineering/SKILL.md)
**Выбор и правильная реализация криптографических примитивов:**
- Матрица выбора AEAD-шифров: AES-256-GCM (аппаратное ускорение AES-NI), ChaCha20-Poly1305 (софтверная защита от тайминг-атак), XChaCha20-Poly1305 (192-битный случайный nonce), AES-GCM-SIV (устойчивость к повторению nonce).
- Асимметричные примитивы: X25519 (ECDH) и Ed25519 (цифровые подписи).
- Пост-квантовая криптография (PQC): гибридные схемы X25519 + ML-KEM-768 (Kyber) по стандартам NIST FIPS 203.
- Криптографически стойкие генераторы случайных чисел (CSPRNG) и список запрещенных алгоритмов (ECB, CBC без HMAC, MD5, RC4).

### 4. [`secure-application-architecture/`](secure-application-architecture/SKILL.md)
**Архитектура защищенных приложений и изоляция процессов:**
- Моделирование угроз STRIDE для криптографического ПО.
- Изоляция процессов: вынос крипто-ядра с мастер-ключами в отдельный изолированный бекенд/воркер с ограниченными правами, отделенный от UI (Electron, Tauri, Qt).
- Безопасная работа с временными файлами: потоковая обработка в памяти без записи на диск, отказ от стандартного `/tmp` из-за особенностей износа SSD.
- Принцип Fail-Closed: мгновенное уничтожение частично расшифрованных файлов при сбое аутентификации.

### 5. [`side-channel-and-anti-tamper-defense/`](side-channel-and-anti-tamper-defense/SKILL.md)
**Защита от сторонних каналов и реверс-инжиниринга:**
- Constant-time программирование: запрет ветвлений (`if`), табличных лукапов (`sbox[k]`) и делений на секретных данных для защиты от атак по времени (timing & cache attacks).
- Защита от bit-flipping атак на шифротекст через принудительный AEAD.
- Флаги компилятора для защиты бинарников (Stack Canaries, Full RELRO, NX/DEP, ASLR, Control Flow Guard).

### 6. [`cryptographic-audit-and-fuzzing/`](cryptographic-audit-and-fuzzing/SKILL.md)
**Фаззинг, тестирование и аудит безопасности:**
- Фаззинг бинарных парсеров кастомных форматов с помощью libFuzzer / AFL++ / cargo-fuzz с адресным санитайзером (ASan).
- Тестовые векторы Known Answer Tests (KAT) и тесты Google Project Wycheproof.
- Финальный чеклист готовности приложения к безопасному релизу.

### 7. [`network-security-audit/`](network-security-audit/SKILL.md)
**Аудит программы и задумки, работающей с сетью:**
- Инвентаризация сети: входящие листенеры, исходящие соединения, протоколы, парсеры, идентичность — до любой оценки.
- Threat model по границам доверия (STRIDE), а не по файлам; отдельный блок «задумка, а не только код».
- Статический разбор сетевого кода: TLS и hostname verification, SSRF и DNS rebinding, редиректы, request smuggling, WebSocket Origin, gRPC deadlines, лимиты парсинга, authz на каждый объект, rate limiting, retry-штормы, fail-open конфиги.
- Динамическая проверка только на своём стенде: ZAP baseline/API, nuclei со своими шаблонами, mitmproxy/tshark, ручная проверка таймаутов и отказов зависимостей.
- Логи, телеметрия и приватность: что писать, что нельзя, GDPR-минимизация, готовность детекта через Sigma/Suricata/Zeek.
- Supply chain и секреты: Trivy, Gitleaks, TruffleHog, OSV, lockfile, install-скрипты, base image по дайджесту.
- Ethics- и legal-гейт до любых активных тестов: RFC 1087, Menlo Report, disclose.io, ACM Code, GDPR Art. 32, §202a StGB, NIS2, CRA; проверка ToS/robots и согласия третьих сторон.
- Формат отчёта: находка = CWE/ASVS + место + триггер + impact + evidence + фикс + способ проверки; severity по CVSS v4.
- Реестр источников (`references/source-pack.md`, 40+ репозиториев с звёздами и лицензиями) и построчный чеклист (`references/network-checklist.md`) с привязкой к CWE.
