# Crypto Engineering — криптоархитектура, аудит и миграция

Категория про **криптографию как инженерию**: какую примитиву выбрать, как хранить и ротировать ключи, как проверить чужой код на тайминг-утечки, и как пережить переход на пост-квантовую криптографию.

Дополняет существующий [`security-crypto/`](../security-crypto/README.md): там **принципы** (AEAD, HKDF, Argon2id, контракты), здесь — **исполнение и проверка** (аудит, сканеры, процедуры, инструменты).

**13 навыков.**

## Когда подключать

| Задача | Навык |
| --- | --- |
| Спроектировать крипто: алгоритм, ключи, E2EE, KMS, TLS, PQC | [`implementing-end-to-end-encryption-for-messaging`](implementing-end-to-end-encryption-for-messaging/SKILL.md) + [`migrating-to-post-quantum-cryptography`](migrating-to-post-quantum-cryptography/SKILL.md) |
| Проверить код на тайминг-атаки и ветвления по секретам | [`constant-time-analysis`](constant-time-analysis/SKILL.md) |
| Найти незанулённые секреты в памяти, включая съеденные оптимизатором | [`zeroize-audit`](zeroize-audit/SKILL.md) |
| Найти опасные API и footgun-конфиги в крипто-библиотеках | [`sharp-edges`](sharp-edges/SKILL.md) |
| Оценить TLS-конфигурацию сервера (sslyze) | [`performing-ssl-tls-security-assessment`](performing-ssl-tls-security-assessment/SKILL.md) |
| Аудит TLS, cipher suites, крипто-кода, PQC-гайденс | [`crypto-analysis`](crypto-analysis/SKILL.md) |
| Поднять собственный CA на OpenSSL | [`configuring-certificate-authority-with-openssl`](configuring-certificate-authority-with-openssl/SKILL.md) |
| Настроить mTLS между сервисами | [`implementing-mtls-for-zero-trust-services`](implementing-mtls-for-zero-trust-services/SKILL.md) |
| Шифрование данных на диске (AES-256-GCM) | [`implementing-aes-encryption-for-data-at-rest`](implementing-aes-encryption-for-data-at-rest/SKILL.md) |
| Сквозное шифрование в мессенджере/чате | [`implementing-end-to-end-encryption-for-messaging`](implementing-end-to-end-encryption-for-messaging/SKILL.md) |
| Подписи на Ed25519 | [`implementing-digital-signatures-with-ed25519`](implementing-digital-signatures-with-ed25519/SKILL.md) |
| Секреты: Vault, динамические креды, ротация | [`implementing-secrets-management-with-vault`](implementing-secrets-management-with-vault/SKILL.md) |
| Миграция на пост-квантовую криптографию | [`migrating-to-post-quantum-cryptography`](migrating-to-post-quantum-cryptography/SKILL.md) |
| Криптоанализ: lattice, padding oracle, слабый RNG, подделка подписей | [`cryptography`](cryptography/SKILL.md) |

## Что внутри

- **`constant-time-analysis`** — 8 справочников по языкам (C compiled, Python, JS, Kotlin, Swift, Ruby, PHP, VM-compiled). Ищет деление на секретах, ветвления по секретным значениям, secret-dependent индексацию, утечки через кэш.
- **`zeroize-audit`** — 6 справочников, включая `ir-analysis.md` и `rust-zeroization-patterns.md`. Ловит не только отсутствие `explicit_bzero`, но и случаи, когда зануление **вырезал компилятор**.
- **`sharp-edges`** — 16 справочников по категориям опасных API: что считается footgun, как переписать, как проверить конфиг.
- **`cryptography`** (Transilience) — практический криптоанализ: AGCD-решётки, факторизация по квадрату дискриминанта, GF(2)-линейный коллапс самодельных шифров, Piret-Quisquater DFA, восстановление Shamir-секрета над составным модулем. Плюс 112 КБ готовых сценариев в `reference/scenarios/`.
- **`crypto-analysis`** — аудит TLS и крипто-кода с `tls_auditor.py` (16 КБ), чек-листы «no hardcoded keys / no ECB / nonce per operation / authenticated encryption / verify=True».
- **`migrating-to-post-quantum-cryptography`** — гибридные схемы, ML-KEM/ML-DSA, инвентаризация крипто-инвентаря, приоритизация по сроку секретности данных.
- **`implementing-secrets-management-with-vault`** — динамические креды, движки секретов, ротация, интеграция с приложениями.

## Чем отличается от `security-crypto/`

| `security-crypto/` (существующий) | `crypto-engineering/` (новый) |
| --- | --- |
| «Как правильно спроектировать» — принципы и контракты | «Как проверить и внедрить» — аудит, процедуры, инструменты |
| 6 навыков, теория крипто-примитивов | 13 навыков, включая статический анализ и PQC-миграцию |
| Нет инструментов | Есть: `tls_auditor.py`, `agent.py`, 30+ справочников |

## Лицензии и атрибуция

| Источник | Лицензия | Навыки |
| --- | --- | --- |
| [mukul975/Anthropic-Cybersecurity-Skills](https://github.com/mukul975/Anthropic-Cybersecurity-Skills) | Apache-2.0 | `performing-ssl-tls-security-assessment`, `implementing-secrets-management-with-vault`, `configuring-certificate-authority-with-openssl`, `implementing-aes-encryption-for-data-at-rest`, `implementing-end-to-end-encryption-for-messaging`, `implementing-mtls-for-zero-trust-services`, `migrating-to-post-quantum-cryptography`, `implementing-digital-signatures-with-ed25519` |
| [Masriyan/Claude-Code-CyberSecurity-Skill](https://github.com/Masriyan/Claude-Code-CyberSecurity-Skill) | MIT | `crypto-analysis` (был `13-crypto-analysis`) |
| [transilienceai/communitytools](https://github.com/transilienceai/communitytools) | MIT | `cryptography` |
| [trailofbits/skills](https://github.com/trailofbits/skills) | **CC-BY-SA-4.0** | `constant-time-analysis`, `zeroize-audit`, `sharp-edges` |

### Внимание: CC-BY-SA-4.0

Три навыка Trail of Bits распространяются под **CC-BY-SA-4.0**, а не MIT/Apache. Это копилефт: производные работы от них должны распространяться под той же лицензией, атрибуция обязательна. Внутри папок лежат оригинальные `LICENSE` — не удаляй их.

Если политика репозитория требует единой лицензии, эти три навыка нужно вынести в отдельную зависимость (git submodule или ссылка на установку), а не держать копией. Остальные 26 навыков категории — MIT/Apache-2.0, ограничений нет.

## Что сюда не вошло и почему

- **`regenscheid/crypto-analysis-skills`** (163 навыка, SAT/SMT, lattice, code-based) — несопоставимая глубина, но 0★ и 0 форков: высокий риск заброшенности. Как справочник — да, как зависимость — нет.
- **`ziyang-theory/cryptography-research-skills`**, **`RiaoMike/crypto-research-agent-skills`** — про написание и рецензирование криптографических статей, а не про код.
- **`NiobiumInc/niobium-skills`** (FHE на OpenFHE) — одно узкое направление, 1 навык.
- **`simota/agent-skills/crypt`** — хороший навык проектирования, но метафоричное имя и чужая архитектура паков; его функцию закрывает `crypto-architecture` + `cryptography`.
