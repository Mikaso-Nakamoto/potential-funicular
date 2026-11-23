# Vault-only launcher integration preview

## Что добавлено

Новый верхнеуровневый `Start-VaultWorkspace.ps1` — отдельный entry point, НЕ замена
Start-Workspace.ps1 и меню. Он требует Runtime/private/workspace.vault; не читает
xray.json и не откатывается к нему при отсутствии/ошибке vault. Пароль скрытый,
SecureString освобождается сразу после чтения. URL/HWID не нужны при запуске;
subscription из документа не сохраняется в переменной сессии после извлечения config.

Порядок: общий exclusive .session.lock → проверка занятости профиля → разблокировка →
policy/нативный Xray -test через stdin → для полного запуска ownership Xray handle →
доставка config через stdin → проверка loopback SOCKS 17890, принадлежащего этому PID →
LibreWolf с прежними proxy prefs → ожидание закрытия браузера → Dispose Xray и
подтверждение cleanup → освобождение lock. Изменений политики TLS/прокси нет.
Config не пишется в временный JSON, не попадает в аргументы/native diagnostics.

`-ValidateOnly` выполняет только разблокировку/policy/Xray -test. Не запускает
туннель/браузер, не создаёт профиль, не проверяет remote connectivity. Может создать
.session.lock и private/tmp для компиляции helper на том же диске. Тесты используют
только вымышленный Runtime в owned scratch, не существующий Runtime пользователя.

Ownership-first API BeginRun/SendForRun (и PS wrappers Open/Send) позволяет launcher
сохранить handle до передачи секретов. При ошибке доставки остаётся возможность
проверить CleanupConfirmed. Если cleanup не подтверждён, новый launcher сохраняет
lock и ждёт; принудительное закрытие shell НЕ безопасный способ завершения.
Это не Job Object: общий lifecycle-revью и тесты дерева процессов ещё обязательны.

## Границы готовности

Эта новая связка Windows/C# здесь не исполнялась. Старые R3 vault/последний успешный
stdin отчёт не подтверждают новый launcher и ownership API. Legacy launcher,
обновление и меню не переключались: вся установка пока НЕ защищена паролем.
Старые plaintext-копии/другой launcher остаются обходом, браузерный профиль не шифруется.
Нет encrypted refresh/node selection, протокола обновления/backup, удаления исходников
или гарантии power-loss durability. Управляемые строки не гарантированно стираются.
Не делать миграцию и не удалять рабочий конфиг по результату этого тестового пакета.

## Что тестируется сейчас

Start-VaultLaunchTests устанавливает ту же закреплённую официальную MSVC libsodium
(проверка импорта/подписи Microsoft runtime без его установки), затем в ДВУХ свежих
неинтерактивных PowerShell 5.1 процессах:
1. Повторяет transport regression с ownership-first live-session API и при -XrayExe
   реальный Xray -test с синтетическим example.invalid config.
2. Test-VaultLaunch вызывает настоящий новый launcher с -ValidateOnly на вымышленных
   данных. Тестовый harness подменяет только Read-Host, возвращая временную SecureString;
   в самом launcher нет параметра/файла/env для пароля или тестовых обходов.

Положительный baseline: generated phrase → настоящий encrypted vault → policy →
stdin fake Xray. Неверный legacy xray.json намеренно присутствует, но игнорируется.
Негативные: неверный пароль, отсутствующий/повреждённый/занятый vault, аутентифицированный
небезопасный config, занятый session lock. Во всех них child не должен запускаться.
Отдельно native rejection после успешного unlock. Проверяется освобождение lock
после ValidateOnly и сохранность vault/legacy decoy. Никаких реальных URL/UUID/ключей.

Полный live vault→SOCKS→реальный браузер в этом наборе НЕ выполняется: сперва нужен
PASS синтетической интеграции и ревью cleanup. Fake EXE компилируется только в stage;
защиту Windows ради него не отключать, если заблокирован — прислать ошибку.

## Запуск тестов

Windows PowerShell 5.1 x64, обычный пользователь. Новый пустой Vault-Launch-Test,
не поверх предыдущих каталогов/рабочей установки. Сохранить ZIP в Z:\Iran\Browser.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Unblock-File -LiteralPath 'Z:\Iran\Browser\VIC-A-Vault-Launch-Tests.zip'
    Expand-Archive -LiteralPath 'Z:\Iran\Browser\VIC-A-Vault-Launch-Tests.zip' -DestinationPath 'Z:\Iran\Browser\Vault-Launch-Test'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File 'Z:\Iran\Browser\Vault-Launch-Test\vault-preview\Start-VaultLaunchTests.ps1' -XrayExe 'Z:\Iran\Browser\Runtime\Xray\xray.exe'
}
```

Если упал установщик — дальнейшие наборы не запускаются. Если transport упал —
integration не запускается. Повторная установка в существующий lib запрещена.
Отчёты из Z:\Iran\Browser\Vault-Launch-Test\vault-preview:
- vault-launch-install-report.txt;
- xray-pipe-test-report.txt;
- vault-launch-test-report.txt (только если дошло до него).
Прислать созданные отчёты; реальные конфиги/подписку/пароль не присылать.
Повторить ТОЛЬКО integration после успешной установки можно отдельным новым
powershell.exe -NoProfile -NonInteractive -File Test-VaultLaunch.ps1 из этого же
каталога, не повторяя Start-VaultLaunchTests. Делать это после разбора причины сбоя.

## Когда-нибудь полный запуск (НЕ команда для текущей проверки)

После подтверждения интеграционных/lifecycle тестов и отдельной подготовки
зашифрованной копии возможен Start-VaultWorkspace.ps1 -Root Z:\Iran\Browser\Runtime.
Сейчас это описание интерфейса для ревью, а не рекомендация запускать на реальных
секретах. Исходный launcher и подписку вручную не переделывать.
