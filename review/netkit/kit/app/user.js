// LibreWolf-USB — профиль браузера работает ТОЛЬКО через локальный SOCKS-прокси Xray.
// Этот файл копируется в profile\ при каждом запуске START.bat; вручную не править.

// --- прокси: без него браузер в интернет не ходит вообще ---
user_pref("network.proxy.type", 1);                  // ручной прокси (0=никак, 5=системный — запрещаем)
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", 10808);
user_pref("network.proxy.socks_version", 5);
user_pref("network.proxy.socks_remote_dns", true);   // DNS тоже через прокси (утечки DNS нет)

// --- прочие утечки и следы ---
user_pref("media.peerconnection.enabled", false);    // WebRTC выкл (не светит IP)
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("browser.cache.disk.enable", false);       // кэш только в ОЗУ, не на диске ПК
user_pref("browser.cache.memory.enable", true);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.interval", 300000);   // сессия пишется раз в 5 мин, а не каждые 15 с — меньше мелкой записи на флешку
user_pref("browser.startup.page", 0);                // не восстанавливать сессию
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.pagethumbnails.capturing_disabled", true);
user_pref("app.update.enabled", false);
user_pref("extensions.update.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);

// --- «грязные ПК»: НИКАКИХ реальных аккаунтов и синхронизации ---
user_pref("identity.fxaccounts.enabled", false);     // аккаунты Firefox выключены
user_pref("signon.rememberSignons", false);          // НЕ сохранять пароли (кража профиля = кража паролей)
user_pref("browser.formfill.enable", false);         // не запоминать данные форм
user_pref("extensions.webservice.discoverURL", "");

// --- выход ТОЛЬКО через туннель (аудит F-01) ---
user_pref("network.proxy.failover_direct", false);   // прокси мёртв -> НЕ идти напрямую (иначе системные запросы утекают)
user_pref("network.proxy.allow_hijacking_localhost", true);
user_pref("network.http.http3.enable", false);        // QUIC идёт по UDP мимо SOCKS
user_pref("network.trr.mode", 5);                     // 5 = DoH ВЫКЛЮЧЕН жёстко; имена резолвит VPN-сервер (socks_remote_dns)
                                                     // (0 значило «по умолчанию», и браузер мог уйти на DoH-сервер провайдера)
user_pref("network.proxy.no_proxies_on", "");         // никаких исключений из прокси
user_pref("security.enterprise_roots.enabled", false); // НЕ доверять корневым сертификатам, установленным в Windows:
                                                       // иначе прокси колледжа/антивирус может расшифровать HTTPS
user_pref("network.predictor.enabled", false);         // «предсказатель» сети не пишет историю запросов
user_pref("network.predictor.enable-prefetch", false);
