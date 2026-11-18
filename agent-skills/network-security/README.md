# Network Security — анализ трафика, IDS/IPS, сетевой периметр

Категория про **сеть как наблюдаемую поверхность**: что реально летит по проводу, чем это ловить, как проверить периметр и как вести работу по нему легально.

**12 навыков.** Все тексты — на английском (как в апстримах), описания здесь — на русском.

## Когда подключать

| Задача | Навык |
| --- | --- |
| Разобрать pcap/pcapng, найти C2, эксфильтрацию, креды в открытом виде | [`analyzing-network-traffic-with-wireshark`](analyzing-network-traffic-with-wireshark/SKILL.md) |
| Скриптовать разбор пакетов и писать детекторы на Python | [`analyzing-network-packets-with-scapy`](analyzing-network-packets-with-scapy/SKILL.md) |
| Поставить мониторинг и детект на поток: Zeek-скрипты, логи, beaconing | [`performing-network-traffic-analysis-with-zeek`](performing-network-traffic-analysis-with-zeek/SKILL.md) |
| Правила IDS/IPS: Suricata, сигнатуры, baseline | [`configuring-suricata-for-network-monitoring`](configuring-suricata-for-network-monitoring/SKILL.md) |
| Найти DNS-туннель и эксфильтрацию по DNS-запросам | [`detecting-dns-exfiltration-with-dns-query-analysis`](detecting-dns-exfiltration-with-dns-query-analysis/SKILL.md) |
| Просканировать сеть и не утонуть в выводе | [`scanning-network-with-nmap-advanced`](scanning-network-with-nmap-advanced/SKILL.md) |
| Проверить TLS-инспекцию, расшифровку и подмену сертификатов | [`performing-ssl-tls-inspection-configuration`](performing-ssl-tls-inspection-configuration/SKILL.md) |
| Оценить Wi-Fi: хендшейки, PMKID, точки доступа | [`conducting-wireless-network-penetration-test`](conducting-wireless-network-penetration-test/SKILL.md) |
| Свести всё вместе: пакеты + правила + файрвол в одном отчёте | [`network-security-ops`](network-security-ops/SKILL.md) |
| Аудит правил файрвола: iptables, nftables, pf, security groups | [`firewall-review`](firewall-review/SKILL.md) |
| Разведка перед работой: поддомены, DNS, стек, топология | [`reconnaissance`](reconnaissance/SKILL.md) |
| Скоупинг и проведение пентеста, отчётность | [`pentest-engagement`](pentest-engagement/SKILL.md) |

## Что внутри

- **`analyzing-network-traffic-with-wireshark`** — tshark от и до: ring buffer, multi-interface capture, display-фильтры под C2, SMB lateral movement, поиск кред в cleartext, извлечение файлов.
- **`performing-network-traffic-analysis-with-zeek`** — Zeek-скрипты, логи conn/dns/http/ssl, детект долгих соединений и регулярных интервалов.
- **`configuring-suricata-for-network-monitoring`** — правила, ревизия сигнатур, false-positive контроль, запуск в IDS и IPS режимах.
- **`detecting-dns-exfiltration-with-dns-query-analysis`** — энтропия поддоменов, TXT-злоупотребления, DoH/DoT-обходы, базлайны.
- **`network-security-ops`** — самый широкий: PCAP-анализ + Snort/Suricata/Zeek + аудит файрволов. Есть **явный контракт доказательств** (`observed` / `inferred` / `unverified`, SHA-256 артефакта, время сбора) и режимы работы `offline` / `passive` / `authorized-active` / `simulation`. Готовые `pcap_analyzer.py`.
- **`firewall-review`** — 11 подкаталогов справочников: парсеры, детекторы, compliance-маппинг, шаблоны отчётов. Проверка правил не «на глаз», а по структуре.
- **`pentest-engagement`** — единственный в подборке навык про **процесс**: скоуп, разрешения, этапы, приоритизация рисков.

## Требования

Часть навыков ставит инструменты (`scapy`, `dpkt`, `sslyze`, `tshark`, Suricata, Zeek, nmap). Запуск активных действий требует авторизации на целевой сети — это явно прописано в самих навыках.

## Лицензии и атрибуция

| Источник | Лицензия | Навыки |
| --- | --- | --- |
| [mukul975/Anthropic-Cybersecurity-Skills](https://github.com/mukul975/Anthropic-Cybersecurity-Skills) | Apache-2.0 | 8 навыков с префиксами `analyzing-`, `performing-`, `configuring-`, `detecting-`, `scanning-`, `conducting-` |
| [Masriyan/Claude-Code-CyberSecurity-Skill](https://github.com/Masriyan/Claude-Code-CyberSecurity-Skill) | MIT | `network-security-ops` (был `08-network-security`) |
| [transilienceai/communitytools](https://github.com/transilienceai/communitytools) | MIT | `firewall-review`, `reconnaissance`, `pentest-engagement` |

## Что сюда не вошло и почему

- **Active Directory** (`Claude-AD`, Kerberos, ADCS, NTLM relay) — это identity, а не сеть; тема заслуживает отдельной категории.
- **Cloud/K8s network policies** — пересекается с контейнерной безопасностью, не с анализом трафика.
- **Malware traffic analysis** — 22 навыка про реверс малвари; ближе к `Awesome-REA`, чем к сетевой инженерии.
