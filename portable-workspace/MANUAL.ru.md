# Ручной ввод UUID и параметров рабочего узла

Configure-ManualNode.ps1 положите рядом с Workspace.Common.ps1 и Start-Workspace.ps1, в Z:\Iran\Browser. Установленный Runtime не удаляйте. Подписка при ручном вводе не используется.

Запуск из обычного PowerShell без администратора:

```powershell
Unblock-File -LiteralPath 'Z:\Iran\Browser\Configure-ManualNode.ps1'
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File 'Z:\Iran\Browser\Configure-ManualNode.ps1' -Root 'Z:\Iran\Browser\Runtime'
```

UUID и GUID здесь обозначают один идентификатор, он вводится один раз в скрытом приглашении. Значения берите из реально работающего узла Inci: адрес сервера (не URL подписки), порт, transport, security, SNI, flow. Для REALITY также нужны публичный ключ pbk и shortId. Серверный приватный ключ не нужен и не должен покидать сервер. Для WS могут понадобиться path и Host; для TLS — ALPN.

Поддерживаются TLS/TCP, TLS/WS и REALITY/TCP, как в текущем парсере. security=none, gRPC/XHTTP и неизвестные настройки не преобразуются в TLS автоматически. Если рабочий узел использует такие параметры, нужна отдельная поддержка реальной схемы. Не подставляйте выдуманные SNI или ключи.

Скрипт проверит политику и xray run -test, затем заменит конфигурацию, не запуская браузер. После успешного сохранения:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File 'Z:\Iran\Browser\Start-Workspace.ps1' -Root 'Z:\Iran\Browser\Runtime'
```

На SSD конфигурация хранится открыто. Скрытый ввод UUID не гарантирует удаления копий из памяти. Первое испытание — дома без входа в аккаунты, с проверкой IP/DNS и отказа доступа при остановке Xray. Общие незакрытые ограничения SOCKS без авторизации и аварийного завершения PowerShell сохраняются. Новый ручной мастер прошёл только статический синтаксический разбор, на Windows не исполнялся.
