#!/usr/bin/env python3
"""Локальная словарная проверка хешей через Hashcat; вход и отчёт на носителе."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Sequence


# Эти режимы поддерживаются Hashcat 6.2.6 и не принуждают вывод пароля
# независимо от --outfile-format=1. Список намеренно ограничен.
HASH_MODES = {
    0: "MD5 (без соли)",
    100: "SHA-1 (без соли)",
    500: "md5crypt ($1$)",
    1000: "NTLM",
    1400: "SHA-256 (без соли)",
    1700: "SHA-512 (без соли)",
    1800: "sha512crypt ($6$)",
    2100: "DCC2 / MS Cache 2",
    3200: "bcrypt (семейство $2*$)",
    7400: "sha256crypt ($5$)",
}
MIN_HASHCAT_VERSION = (6, 2, 6)

# Небольшой публичный список; он не претендует на полноту.
COMMON_PASSWORDS = (
    "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999",
    "1234", "4321", "1212", "1122",
    "00000", "11111", "12345", "54321",
    "000000", "111111", "123456", "654321", "112233", "121212", "123123",
    "0000000", "1111111", "1234567", "7654321",
    "00000000", "11111111", "12345678", "87654321", "12121212", "11223344",
    "12344321", "13243546",
    "000000000", "111111111", "123456789", "987654321",
    "0000000000", "1111111111", "1234567890", "0987654321",
    "qwerty", "qwerty123", "password", "password1", "Password1", "admin", "admin123",
    "letmein", "welcome", "iloveyou",
)


class AuditError(Exception):
    """Ошибка подготовки или сохранения результатов проверки."""


@dataclass(frozen=True)
class HashcatStatus:
    status_code: int
    matched: int
    loaded: int
    progress_done: Optional[int]
    progress_total: Optional[int]
    rejected: Optional[int]


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("ожидается целое число") from exc
    if number <= 0:
        raise argparse.ArgumentTypeError("значение должно быть больше нуля")
    return number


def make_parser() -> argparse.ArgumentParser:
    modes = ", ".join(f"{number}: {name}" for number, name in HASH_MODES.items())
    parser = argparse.ArgumentParser(
        description=(
            "Офлайн-проверка уже извлечённых хешей по локальному словарю. "
            "Исходные файлы и результаты должны находиться на указанном носителе."
        ),
        epilog=(f"Поддерживаемые режимы Hashcat: {modes}. "
                "Сценарий с подсказкой: python3 usb_audit.py hint --help."),
    )
    parser.add_argument("--usb", required=True, help="путь к смонтированному каталогу данных")
    parser.add_argument(
        "--check", action="store_true",
        help="проверить доступность записи и Hashcat без проверки хешей",
    )
    parser.add_argument(
        "--mode", type=int, choices=sorted(HASH_MODES),
        help="числовой режим Hashcat для формата хешей; обязателен, кроме --check",
    )
    parser.add_argument(
        "--hashes", default="hashes.txt", help="файл хешей на флешке (по умолчанию hashes.txt)"
    )
    parser.add_argument(
        "--wordlist", help="словарь на флешке (по умолчанию wordlist.txt; несовместим с --weak)"
    )
    parser.add_argument(
        "--weak", action="store_true",
        help="использовать встроенный небольшой список распространённых паролей вместо словаря",
    )
    parser.add_argument(
        "--show-passwords", action="store_true",
        help="показать найденные пароли в терминале (только вместе с --weak)",
    )
    parser.add_argument(
        "--hashcat", default="hashcat",
        help="исполняемый Hashcat из PATH или путь к нему; относительные пути ищутся на флешке",
    )
    parser.add_argument(
        "--username", action="store_true", help="входные строки имеют вид имя:хеш"
    )
    parser.add_argument("--cpu", action="store_true", help="использовать устройства OpenCL CPU")
    parser.add_argument(
        "--runtime", type=positive_int, metavar="СЕКУНДЫ",
        help="остановить Hashcat по истечении указанного времени",
    )
    return parser


def within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def checked_root(value: str) -> Path:
    try:
        root = Path(value).expanduser().resolve(strict=True)
    except OSError as exc:
        raise AuditError(f"Носитель недоступен: {value}") from exc
    if not root.is_dir():
        raise AuditError(f"Путь к носителю не является каталогом: {root}")
    return root


def ensure_writable(root: Path) -> None:
    # Фактическое создание файла надёжнее os.access() на read-only носителях.
    # TemporaryFile удаляется при закрытии, включая выход по исключению.
    try:
        with tempfile.TemporaryFile(prefix=".usb-audit-check-", dir=root) as stream:
            stream.write(b"\0")
            stream.flush()
    except OSError as exc:
        raise AuditError(
            f"Каталог данных недоступен для записи: {root}. "
            "Выберите смонтированный раздел с записью; загрузочный раздел Kali Live может быть read-only."
        ) from exc


def filesystem_type(root: Path) -> Optional[str]:
    """Тип файловой системы для предупреждения; сохранность данных не доказывает."""
    if not sys.platform.startswith("linux"):
        return None
    findmnt = shutil.which("findmnt")
    if findmnt is None:
        return None
    try:
        result = subprocess.run(
            [findmnt, "--noheadings", "--raw", "--target", str(root), "--output", "FSTYPE"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", errors="replace", timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    value = result.stdout.strip()
    if result.returncode != 0 or not re.fullmatch(r"[A-Za-z0-9_.+-]+", value):
        return None
    return value


def warn_if_volatile(fstype: Optional[str]) -> None:
    if fstype == "tmpfs":
        print("Внимание: каталог находится в tmpfs; данные исчезнут после перезагрузки.",
              file=sys.stderr)
    elif fstype in ("overlay", "aufs"):
        print("Внимание: каталог находится в overlay. В Kali Live без настроенного persistence "
              "данные могут исчезнуть после перезагрузки.", file=sys.stderr)


def checked_input(root: Path, value: str, label: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    try:
        path = path.resolve(strict=True)
    except OSError as exc:
        raise AuditError(f"{label} недоступен: {value}") from exc
    if not within(path, root):
        raise AuditError(f"{label} должен находиться внутри указанного носителя: {value}")
    if not path.is_file():
        raise AuditError(f"{label} не является обычным файлом: {path}")
    try:
        with path.open("rb") as stream:
            stream.read(1)
    except OSError as exc:
        raise AuditError(f"Не удалось прочитать {label.lower()}: {path}") from exc
    return path


def count_nonempty_lines(path: Path) -> int:
    try:
        with path.open("rb") as stream:
            return sum(1 for line in stream if line.strip())
    except OSError as exc:
        raise AuditError(f"Не удалось прочитать файл: {path}") from exc


def looks_like_mode(line: bytes, mode: int, username: bool = False) -> bool:
    """Предварительно проверяет синтаксис NTLM/DCC2, не определяя алгоритм."""
    if mode not in (1000, 2100):
        return True

    value = line.strip()
    if mode == 1000 and value.count(b":") == 6:
        # Hashcat также распознаёт pwdump: name:rid:lm:nt:::.
        fields = value.split(b":")
        if len(fields[2]) == 32 or len(fields[3]) == 32:
            return re.fullmatch(rb"[0-9a-fA-F]{32}", fields[3]) is not None

    if username:
        name, separator, value = value.partition(b":")
        if not separator or not name:
            return False

    if mode == 1000:
        # По длине и алфавиту нельзя отличить NTLM от, например, MD5.
        return re.fullmatch(rb"[0-9a-fA-F]{32}", value) is not None

    if not value.startswith(b"$DCC2$"):
        return False
    iterations, separator, rest = value[len(b"$DCC2$"):].partition(b"#")
    salt, separator2, digest = rest.rpartition(b"#")
    return (
        bool(separator and separator2)
        and re.fullmatch(rb"[0-9]{1,6}", iterations) is not None
        and int(iterations) > 0
        and len(salt) <= 256
        and re.fullmatch(rb"[0-9a-fA-F]{32}", digest) is not None
    )


def validate_hashes(path: Path, mode: int, username: bool) -> int:
    """Считает непустые строки и проверяет весь файл для режимов 1000/2100."""
    count = 0
    try:
        with path.open("rb") as stream:
            for line_no, line in enumerate(stream, start=1):
                if not line.strip():
                    continue
                count += 1
                if not looks_like_mode(line, mode, username):
                    raise AuditError(
                        f"Строка {line_no} файла {path.name} не соответствует синтаксису "
                        f"режима {mode} ({HASH_MODES[mode]}). Проверьте формат, --username "
                        "и разделение разных типов хешей по файлам."
                    )
    except OSError as exc:
        raise AuditError(f"Не удалось прочитать файл: {path}") from exc
    return count


def find_hashcat(value: str, root: Path) -> Path:
    # Один исполняемый файл, без shell и без разбора пользовательских команд.
    path = Path(value).expanduser()
    has_directory = path.is_absolute() or path.parent != Path(".")
    if has_directory:
        candidate = path if path.is_absolute() else root / path
        found = str(candidate) if candidate.is_file() else None
    else:
        found = shutil.which(value)
        if found is None:
            candidate = root / value
            found = str(candidate) if candidate.is_file() else None
    if found is None:
        raise AuditError("Hashcat не найден. Установите его или укажите путь через --hashcat.")
    path = Path(found).resolve()
    if not path.is_file() or (os.name != "nt" and not os.access(path, os.X_OK)):
        raise AuditError(f"Hashcat не является исполняемым файлом: {path}")
    return path


def hashcat_version(executable: Path, root: Path) -> str:
    try:
        result = subprocess.run(
            [str(executable), "--version"], cwd=root, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding="utf-8", errors="replace", timeout=15, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise AuditError(f"Не удалось проверить версию Hashcat: {exc}") from exc
    match = re.search(r"\b(?:v)?(\d+)\.(\d+)\.(\d+)\b", result.stdout)
    if result.returncode != 0 or match is None:
        raise AuditError("Не удалось определить версию Hashcat; требуется версия 6.2.6 или новее.")
    version = tuple(int(part) for part in match.groups())
    if version < MIN_HASHCAT_VERSION:
        raise AuditError("Требуется Hashcat версии 6.2.6 или новее.")
    return match.group(0)


def prepare_run(root: Path) -> Path:
    # resolve() также запрещает ссылку audit-results, ведущую за пределы носителя.
    results = (root / "audit-results").resolve()
    if not within(results, root):
        raise AuditError("Каталог audit-results указывает за пределы носителя.")
    try:
        results.mkdir(mode=0o700, parents=True, exist_ok=True)
        prefix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
        return Path(tempfile.mkdtemp(prefix=prefix, dir=results))
    except OSError as exc:
        raise AuditError(f"Не удалось создать каталог результатов на носителе: {exc}") from exc


def runtime_environment(run_dir: Path) -> dict[str, str]:
    runtime = run_dir / "runtime"
    env = os.environ.copy()
    # Часть сборок Hashcat и драйверов может кэшировать данные вне этих каталогов.
    paths = {
        "HOME": runtime,
        "XDG_CACHE_HOME": runtime / "cache",
        "XDG_DATA_HOME": runtime / "data",
        "TMPDIR": runtime / "tmp",
        "TMP": runtime / "tmp",
        "TEMP": runtime / "tmp",
    }
    if os.name == "nt":
        paths.update({
            "USERPROFILE": runtime,
            "APPDATA": runtime / "appdata",
            "LOCALAPPDATA": runtime / "localappdata",
        })
    try:
        for path in paths.values():
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
    except OSError as exc:
        raise AuditError(f"Не удалось подготовить рабочий каталог на носителе: {exc}") from exc
    env.update({name: str(path) for name, path in paths.items()})
    return env


def parse_status(line: str, session: str) -> Optional[HashcatStatus]:
    try:
        data = json.loads(line)
    except (ValueError, TypeError):
        return None
    if not isinstance(data, dict) or data.get("session") != session:
        return None
    status_code = data.get("status")
    if type(status_code) is not int or status_code < 0:
        return None
    recovered = data.get("recovered_hashes")
    if (
        not isinstance(recovered, list) or len(recovered) != 2
        or any(type(value) is not int or value < 0 for value in recovered)
        or recovered[0] > recovered[1]
    ):
        return None
    progress = data.get("progress")
    if (
        isinstance(progress, list) and len(progress) == 2
        and all(type(value) is int and value >= 0 for value in progress)
    ):
        done, total = progress
    else:
        done, total = None, None
    rejected = data.get("rejected")
    if type(rejected) is not int or rejected < 0:
        rejected = None
    return HashcatStatus(status_code, recovered[0], recovered[1], done, total, rejected)


def make_command(
    executable: Path, args: argparse.Namespace, hashes: Path, wordlist: Path,
    matches: Path, session: str,
) -> list[str]:
    command = [
        str(executable), "--quiet", "--status", "--status-json", "--status-timer", "10",
        "--session", session, "--hash-type", str(args.mode), "--attack-mode", "0",
        "--potfile-disable", "--restore-disable", "--logfile-disable",
    ]
    if args.show_passwords:
        # В этом режиме Hashcat выводит хеш и hex-представление кандидата в pipe,
        # а скрипт записывает на носитель только хеш.
        command.extend(["--outfile-format", "1,3"])
    else:
        command.extend(["--outfile", str(matches), "--outfile-format", "1"])
    if args.username:
        command.append("--username")
    if args.cpu:
        command.extend(["--opencl-device-types", "1"])
    if args.runtime is not None:
        command.extend(["--runtime", str(args.runtime)])
    # Прямые аргументы исключают интерпретацию оболочкой. POSIX-разделители
    # на Windows также позволяют Hashcat корректно формировать JSON статуса.
    command.extend([hashes.as_posix(), wordlist.as_posix()])
    return command


def looks_like_output_hash(value: str, mode: int) -> bool:
    """Проверка записи stdout, чтобы не принять диагностику за совпадение."""
    if not value or "\ufffd" in value or any(ord(c) < 32 or ord(c) == 127 for c in value):
        return False
    encoded = value.encode("utf-8")
    if mode in (1000, 2100):
        return looks_like_mode(encoded, mode) or looks_like_mode(encoded, mode, username=True)
    variants = [value]
    if ":" in value:
        variants.append(value.partition(":")[2])
    widths = {0: 32, 100: 40, 1400: 64, 1700: 128}
    if mode in widths:
        return any(re.fullmatch(rf"[0-9a-fA-F]{{{widths[mode]}}}", v) is not None for v in variants)
    prefixes = {500: ("$1$",), 1800: ("$6$",), 3200: ("$2a$", "$2b$", "$2x$", "$2y$"), 7400: ("$5$",)}
    return mode in prefixes and any(v.startswith(prefixes[mode]) for v in variants)


def parse_weak_match(line: str, mode: int) -> Optional[tuple[str, str]]:
    """Читает запись hash:hex-plain только для известных встроенных кандидатов."""
    hash_value, separator, encoded_password = line.rstrip("\r\n").rpartition(":")
    if (
        not separator or len(encoded_password) > 2 * max(map(len, COMMON_PASSWORDS))
        or not re.fullmatch(r"(?:[0-9a-fA-F]{2})+", encoded_password)
    ):
        return None
    try:
        password = bytes.fromhex(encoded_password).decode("ascii")
    except (ValueError, UnicodeDecodeError):
        return None
    if password not in COMMON_PASSWORDS or not looks_like_output_hash(hash_value, mode):
        return None
    return hash_value, password


def run_hashcat(
    command: Sequence[str], root: Path, env: dict[str, str], session: str,
    *, matches: Optional[Path] = None, reveal_mode: Optional[int] = None,
) -> tuple[int, Optional[HashcatStatus], bool, bool]:
    sink = None
    if reveal_mode is not None:
        if matches is None:
            raise AuditError("Не указан файл совпавших хешей.")
        try:
            sink = matches.open("a", encoding="utf-8", newline="\n")
        except OSError as exc:
            raise AuditError(f"Не удалось открыть файл совпадений: {exc}") from exc
    try:
        process = subprocess.Popen(
            list(command), cwd=root, env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            encoding="utf-8", errors="replace", bufsize=1,
        )
    except OSError as exc:
        if sink is not None:
            sink.close()
        raise AuditError(f"Не удалось запустить Hashcat: {exc}") from exc

    latest = None
    input_warning = False
    output_warning = False
    try:
        assert process.stdout is not None
        for line in process.stdout:
            status = parse_status(line, session)
            if status is None:
                match = None if reveal_mode is None else parse_weak_match(line, reveal_mode)
                if match is not None:
                    hash_value, password = match
                    assert sink is not None
                    sink.write(hash_value + "\n")
                    sink.flush()
                    print(f"Слабый пароль: {json.dumps(password)}; хеш: {json.dumps(hash_value)}", flush=True)
                    continue
                if reveal_mode is not None:
                    possible_hash, separator, _ = line.rstrip("\r\n").rpartition(":")
                    if separator and looks_like_output_hash(possible_hash, reveal_mode):
                        output_warning = True
                        print("Не удалось разобрать запись совпадения Hashcat; содержимое скрыто.",
                              file=sys.stderr, flush=True)
                        continue
                # Типичные предупреждения Hashcat 6/8 о пропущенных строках
                # и изменении файла. Саму строку хеша в отчёт не копируем.
                if line.startswith(("Hashfile '", "Hash parsing error in hashfile:")):
                    input_warning = True
                # Показываем диагностику Hashcat, но не записываем её в отчёт.
                print(line, end="", flush=True)
                continue
            latest = status
            progress = ""
            if status.progress_done is not None and status.progress_total is not None:
                progress = f"; прогресс: {status.progress_done}/{status.progress_total}"
            print(f"Совпадений: {status.matched}/{status.loaded}{progress}", flush=True)
        return process.wait(), latest, input_warning, output_warning
    except KeyboardInterrupt:
        print("\nПроверка прервана пользователем.", file=sys.stderr, flush=True)
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        return 130, latest, input_warning, output_warning
    except OSError as exc:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        raise AuditError(f"Ошибка чтения вывода или записи совпадений: {exc}") from exc
    finally:
        if process.stdout is not None:
            process.stdout.close()
        if sink is not None:
            sink.close()


def outcome_for(returncode: Optional[int]) -> str:
    if returncode == 0:
        return "all_loaded_hashes_matched"
    if returncode == 1:
        return "dictionary_exhausted"
    if returncode in (2, 3, 4, 5, 130):
        return "interrupted"
    return "error"


def check_environment(args: argparse.Namespace) -> int:
    root = checked_root(args.usb)
    fstype = filesystem_type(root)
    print(f"Каталог данных: {root}")
    print(f"Файловая система: {fstype or 'не определена'}")
    warn_if_volatile(fstype)
    ensure_writable(root)
    print("Запись: доступна (временный тестовый файл удалён).")
    executable = find_hashcat(args.hashcat, root)
    version = hashcat_version(executable, root)
    print(f"Hashcat: {version} ({executable})")
    print("Устройства OpenCL не проверены: выполните hashcat -I или <путь-к-hashcat> -I.")
    print("Сохранность после перезагрузки не проверена: подтвердите носитель или persistence.")
    print("Хеши и словарь не обрабатывались.")
    return 0


def audit(args: argparse.Namespace) -> int:
    root = checked_root(args.usb)
    warn_if_volatile(filesystem_type(root))
    ensure_writable(root)
    hashes = checked_input(root, args.hashes, "Файл хешей")
    wordlist = None
    if not args.weak:
        wordlist = checked_input(root, "wordlist.txt" if args.wordlist is None else args.wordlist, "Словарь")
        if hashes == wordlist:
            raise AuditError("Файл хешей и словарь должны быть разными файлами.")
        if wordlist.stat().st_size == 0:
            raise AuditError("Словарь пуст.")
    input_lines = validate_hashes(hashes, args.mode, args.username)
    if input_lines == 0:
        raise AuditError("Файл хешей не содержит непустых строк.")

    executable = find_hashcat(args.hashcat, root)
    version = hashcat_version(executable, root)
    run_dir = prepare_run(root)
    env = runtime_environment(run_dir)
    if args.weak:
        wordlist = run_dir / "weak-candidates.txt"
        try:
            with wordlist.open("x", encoding="ascii", newline="\n") as stream:
                stream.write("\n".join(COMMON_PASSWORDS) + "\n")
        except OSError as exc:
            raise AuditError(f"Не удалось подготовить встроенный словарь: {exc}") from exc
    assert wordlist is not None
    matches = run_dir / "matched-hashes.txt"
    try:
        matches.touch(mode=0o600, exist_ok=False)
    except OSError as exc:
        raise AuditError(f"Не удалось создать файл совпадений: {exc}") from exc

    session = "usb-audit-" + run_dir.name
    command = make_command(executable, args, hashes, wordlist, matches, session)
    started = datetime.now(timezone.utc).isoformat()
    print(f"Результаты: {run_dir}", flush=True)
    print(f"Hashcat {version}; режим {args.mode} ({HASH_MODES[args.mode]}).", flush=True)
    if args.weak:
        print(f"Встроенный список: {len(COMMON_PASSWORDS)} распространённых кандидатов.", flush=True)
    if args.show_passwords:
        print("Найденные пароли будут показаны в терминале; защитите его вывод.", flush=True)
    print("Выполняется словарная проверка; Ctrl+C — остановка.", flush=True)

    error_message = None
    try:
        returncode, status, input_warning, output_warning = run_hashcat(
            command, root, env, session,
            matches=matches if args.show_passwords else None,
            reveal_mode=args.mode if args.show_passwords else None,
        )
    except AuditError as exc:
        returncode, status, input_warning, output_warning = None, None, None, None
        error_message = str(exc)
        print(error_message, file=sys.stderr)

    matched_lines = count_nonempty_lines(matches)
    consistent = None if status is None else matched_lines == status.matched
    # Hashcat может выдать промежуточный статус перед ошибкой или прерыванием.
    expected_final = {0: 6, 1: 5}.get(returncode)
    complete = (
        expected_final is not None and status is not None
        and status.status_code == expected_final and consistent is True
        and status.rejected == 0 and input_warning is False and output_warning is False
    )
    report = {
        "schema_version": 1,
        "started_utc": started,
        "finished_utc": datetime.now(timezone.utc).isoformat(),
        "hashcat_version": version,
        "hash_mode": args.mode,
        "hash_type": HASH_MODES[args.mode],
        "attack": "dictionary",
        "hashes_file": str(hashes.relative_to(root)),
        "wordlist_file": str(wordlist.relative_to(root)),
        "candidate_source": "builtin-weak" if args.weak else "file",
        "passwords_shown_in_terminal": args.show_passwords,
        "username_prefix": args.username,
        "runtime_limit_seconds": args.runtime,
        "input_nonempty_lines": input_lines,
        "loaded_unique_hashes": None if status is None else status.loaded,
        "matched_unique_hashes": None if status is None else status.matched,
        "matched_file_lines": matched_lines,
        "progress": None if status is None else [status.progress_done, status.progress_total],
        "rejected_candidates": None if status is None else status.rejected,
        "input_warning_detected": input_warning,
        "output_warning_detected": output_warning,
        "hashcat_exit_code": returncode,
        "hashcat_status_code": None if status is None else status.status_code,
        "outcome": outcome_for(returncode),
        "matched_file_consistent": consistent,
        "run_complete": complete,
        "error": error_message,
    }
    try:
        (run_dir / "report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        raise AuditError(f"Не удалось сохранить отчёт: {exc}") from exc

    if status is not None:
        print(f"Строк входа: {input_lines}; загружено уникальных хешей: {status.loaded}; "
              f"совпадений: {status.matched}.")
        if status.loaded < input_lines:
            print("Число строк больше числа загруженных хешей: возможны дубликаты или ошибки формата.")
        if status.rejected:
            print(f"Hashcat отклонил кандидатов: {status.rejected}; они не были проверены.")
        elif status.rejected is None:
            print("Число отклонённых кандидатов не получено от Hashcat.", file=sys.stderr)
    else:
        print("Не удалось прочитать итоговый статус Hashcat; счётчики загруженных хешей неизвестны.",
              file=sys.stderr)
    if consistent is False:
        print("Число совпадений в файле не совпадает со статусом Hashcat. Проверьте носитель и вывод выше.",
              file=sys.stderr)
    if input_warning:
        print("Hashcat сообщил о проблемах со входным файлом; проверка отмечена как неполная.", file=sys.stderr)
    if expected_final is not None and status is not None and status.status_code != expected_final:
        print("Нет согласованного итогового статуса Hashcat; проверка отмечена как неполная.", file=sys.stderr)
    if complete:
        if returncode == 0:
            print("Завершено: найдены совпадения для всех загруженных хешей.")
        else:
            print("Завершено: предоставленный словарь исчерпан.")
    else:
        print("Проверка не завершена или результат требует проверки.", file=sys.stderr)
    print(f"Отчёт: {run_dir / 'report.json'}")
    print(f"Совпавшие хеши: {matches}")

    if complete:
        return 0
    return 130 if returncode == 130 else 2


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments and arguments[0] == "hint":
        # Отдельный сценарий намеренно показывает найденный пароль в терминале.
        try:
            from crack_with_hint import main as hint_main
        except ModuleNotFoundError as exc:
            if exc.name != "crack_with_hint":
                raise
            print("Ошибка: для сценария hint положите crack_with_hint.py рядом с usb_audit.py.",
                  file=sys.stderr)
            return 2
        return hint_main(arguments[1:])
    parser = make_parser()
    args = parser.parse_args(arguments)
    if not args.check and args.mode is None:
        parser.error("для проверки хешей необходим --mode (для --check он не нужен)")
    if args.weak and args.wordlist is not None:
        parser.error("--weak и --wordlist нельзя использовать одновременно")
    if args.show_passwords and not args.weak:
        parser.error("--show-passwords работает только вместе с --weak")
    # На POSIX ограничивает права новых файлов, включая файлы процесса Hashcat.
    old_umask = os.umask(0o077)
    try:
        return check_environment(args) if args.check else audit(args)
    except (AuditError, OSError) as exc:
        print(f"Ошибка: {exc}", file=sys.stderr)
        return 2
    finally:
        os.umask(old_umask)


if __name__ == "__main__":
    sys.exit(main())
