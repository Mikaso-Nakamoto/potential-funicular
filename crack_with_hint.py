#!/usr/bin/env python3
"""Проверка одной подготовленной записи: подсказка, правила, словарь и маска.

Только для своих систем или при наличии разрешения владельца. Совпавший пароль
показывается в терминале, но намеренно не записывается в отчёт или potfile.
"""
from __future__ import annotations

import argparse
import getpass
import hashlib
import hmac
import json
import os
import re
import struct
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Sequence

from usb_audit import (
    COMMON_PASSWORDS,
    HASH_MODES,
    AuditError,
    HashcatStatus,
    checked_input,
    checked_root,
    ensure_writable,
    filesystem_type,
    find_hashcat,
    hashcat_version,
    looks_like_mode,
    looks_like_output_hash,
    parse_status,
    positive_int,
    prepare_run,
    runtime_environment,
    warn_if_volatile,
)


# MD4 нужен только для совместимости с историческим NTLM, не для новых паролей.
def md4_digest(data: bytes) -> bytes:
    """Портативный MD4 для NTLM; не зависит от доступности MD4 в OpenSSL."""
    length = len(data)
    padded = data + b"\x80" + b"\x00" * ((55 - length) % 64) + struct.pack("<Q", length * 8)
    state = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476]
    order2 = (0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15)
    order3 = (0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15)

    def rotate(value: int, amount: int) -> int:
        value &= 0xFFFFFFFF
        return ((value << amount) | (value >> (32 - amount))) & 0xFFFFFFFF

    for offset in range(0, len(padded), 64):
        words = struct.unpack("<16I", padded[offset:offset + 64])
        a, b, c, d = state
        for i in range(16):
            f = (b & c) | (~b & d)
            a, b, c, d = d, rotate(a + f + words[i], (3, 7, 11, 19)[i % 4]), b, c
        for i in range(16):
            g = (b & c) | (b & d) | (c & d)
            a, b, c, d = d, rotate(a + g + words[order2[i]] + 0x5A827999,
                                   (3, 5, 9, 13)[i % 4]), b, c
        for i in range(16):
            h = b ^ c ^ d
            a, b, c, d = d, rotate(a + h + words[order3[i]] + 0x6ED9EBA1,
                                   (3, 9, 11, 15)[i % 4]), b, c
        state = [(previous + value) & 0xFFFFFFFF for previous, value in zip(state, (a, b, c, d))]
    return struct.pack("<4I", *state)


def raw_hash_value(target: str, mode: int, username: bool) -> str:
    """Извлекает колонку NTLM из pwdump или убирает префикс имени."""
    if mode == 1000 and target.count(":") == 6:
        fields = target.split(":")
        if len(fields) == 7 and (len(fields[2]) == 32 or len(fields[3]) == 32):
            return fields[3]
    if username:
        _, separator, value = target.partition(":")
        return value if separator else ""
    return target


def compare_hint_locally(hint: str, target: str, mode: int, username: bool) -> Optional[bool]:
    """True/False для поддерживаемых несолёных режимов; None — нужен Hashcat."""
    widths = {0: 32, 100: 40, 1000: 32, 1400: 64, 1700: 128}
    if mode not in widths:
        return None
    value = raw_hash_value(target, mode, username)
    if re.fullmatch(rf"[0-9a-fA-F]{{{widths[mode]}}}", value) is None:
        return None  # Некорректный формат окончательно проверит Hashcat.
    if mode == 1000:
        digest = md4_digest(hint.encode("utf-16-le")).hex()
    else:
        names = {0: "md5", 100: "sha1", 1400: "sha256", 1700: "sha512"}
        try:
            digest = hashlib.new(names[mode], hint.encode("utf-8"), usedforsecurity=False).hexdigest()
        except (ValueError, TypeError):
            return None
    return hmac.compare_digest(digest, value.lower())


def hint_rules() -> list[str]:
    """Ограниченные, детерминированные правила Hashcat без текста подсказки."""
    cases = ("", "l", "u", "c", "t")
    leets = (
        "", "sa4sA4", "sa@sA@", "se3sE3", "si1sI1", "so0sO0",
        "ss5sS5", "ss$sS$", "st7sT7", "sl1sL1",
        "sa4sA4se3sE3si1sI1so0sO0ss5sS5st7sT7sl1sL1",
        "sa@sA@se3sE3si1sI1so0sO0ss$sS$st7sT7sl1sL1",
    )
    common_suffixes = (
        "", "1", "12", "123", "1234", "!", "!!", "@", "#", "$", "123!", "1234!", "1!",
        "2024", "2024!", "2025", "2025!", "2026", "2026!", "2027", "2027!",
    )
    years = [str(year) for year in range(1980, 2031)]
    years += [f"{year % 100:02d}" for year in range(1980, 2031)]
    rules: dict[str, None] = {}

    def add(case: str, leet: str = "", prefix: str = "", suffix: str = "") -> None:
        # В правилах Hashcat $X добавляет символ X, ^X добавляет его в начало.
        rule = case + leet + "".join("^" + char for char in reversed(prefix))
        rule += "".join("$" + char for char in suffix)
        rules[rule or ":"] = None

    for case in cases:
        for leet in leets:
            for suffix in common_suffixes:
                add(case, leet, suffix=suffix)
            for prefix in ("1", "!", "@"):
                add(case, leet, prefix=prefix)
        for suffix in years:
            add(case, suffix=suffix)
    return list(rules)


def password_for_terminal(value: bytes) -> str:
    """Непечатаемые/не UTF-8 данные показываются однозначно в виде $HEX[...]."""
    try:
        text = value.decode("utf-8")
    except UnicodeDecodeError:
        return f"$HEX[{value.hex()}]"
    if (not text.isprintable() and text != "") or text.startswith("$HEX["):
        return f"$HEX[{value.hex()}]"
    try:
        text.encode(sys.stdout.encoding or "utf-8")
    except (UnicodeEncodeError, LookupError):
        return f"$HEX[{value.hex()}]"
    return text


def parse_hashcat_match(line: str, mode: int) -> Optional[tuple[str, bytes]]:
    """Разбирает hash:hex-plain; двоеточия в соли и пароле не теряются."""
    hash_value, separator, encoded = line.rstrip("\r\n").rpartition(":")
    if not separator or len(encoded) > 2048 or re.fullmatch(r"(?:[0-9a-fA-F]{2})*", encoded) is None:
        return None
    if not looks_like_output_hash(hash_value, mode):
        return None
    return hash_value, bytes.fromhex(encoded)


def raw_result_matches_target(hash_value: str, target: str, mode: int, username: bool) -> bool:
    """Для несолёных форматов сверяет запись Hashcat с единственным входом."""
    widths = {0: 32, 100: 40, 1000: 32, 1400: 64, 1700: 128}
    if mode not in widths:
        return True  # Солёные записи Hashcat может нормализовать при выводе.
    expected = raw_hash_value(target, mode, username)
    if re.fullmatch(rf"[0-9a-fA-F]{{{widths[mode]}}}", expected) is None:
        return False
    variants = [hash_value]
    if ":" in hash_value:
        variants.append(hash_value.partition(":")[2])
    return any(re.fullmatch(rf"[0-9a-fA-F]{{{widths[mode]}}}", value) is not None
               and hmac.compare_digest(value.lower(), expected.lower()) for value in variants)


def make_command(
    executable: Path, mode: int, hashes: Path, session: str, *, cpu: bool,
    username: bool, runtime: Optional[int], wordlist: Optional[Path] = None,
    rules: Optional[Path] = None, mask: Optional[str] = None, literal_input: bool = False,
) -> list[str]:
    command = [
        str(executable), "--quiet", "--status", "--status-json", "--status-timer", "10",
        "--session", session, "--hash-type", str(mode), "--outfile-format", "1,3",
        "--potfile-disable", "--restore-disable", "--logfile-disable",
    ]
    if username:
        command.append("--username")
    if cpu:
        command.extend(["--opencl-device-types", "1"])
    if runtime is not None:
        command.extend(["--runtime", str(runtime)])
    if literal_input:
        # Подсказка "$HEX[...]" — это текст, а не запись autohex из словаря.
        command.append("--wordlist-autohex-disable")
    if mask is not None:
        command.extend(["--attack-mode", "3", "--", hashes.as_posix(), mask])
    else:
        command.extend(["--attack-mode", "0"])
        if rules is not None:
            command.extend(["-r", rules.as_posix()])
        command.extend(["--", hashes.as_posix()])
        if wordlist is not None:
            command.append(wordlist.as_posix())
    return command


@dataclass(frozen=True)
class StageResult:
    outcome: str  # matched, exhausted, incomplete или interrupted
    returncode: Optional[int]
    status: Optional[HashcatStatus]
    match: Optional[tuple[str, bytes]]
    input_warning: bool = False
    output_warning: bool = False


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    try:
        process.terminate()
    except ProcessLookupError:
        pass  # Процесс мог завершиться между poll() и terminate().
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            process.kill()
        except ProcessLookupError:
            pass
        process.wait()


def run_stage(
    command: Sequence[str], root: Path, env: dict[str, str], session: str,
    mode: int, candidate_input: Optional[bytes] = None,
) -> StageResult:
    """Подаёт небольшой список по stdin и читает совпадение только из pipe."""
    try:
        process = subprocess.Popen(
            list(command), cwd=root, env=env,
            stdin=subprocess.PIPE if candidate_input is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
        )
    except OSError as exc:
        raise AuditError(f"Hashcat не запустился: {exc}") from exc

    latest = None
    match = None
    input_warning = False
    output_warning = False
    try:
        if candidate_input is not None:
            assert process.stdin is not None
            try:
                remaining = memoryview(candidate_input)
                while remaining:
                    written = process.stdin.write(remaining)
                    if not written:
                        raise BrokenPipeError("Hashcat не принимает входные данные")
                    remaining = remaining[written:]
                process.stdin.close()
            except BrokenPipeError:
                # Дочерний процесс мог завершиться раньше из-за ошибки; читаем его диагностику.
                pass
        assert process.stdout is not None
        for raw in process.stdout:
            line = raw.decode("utf-8", errors="replace")
            status = parse_status(line, session)
            if status is not None:
                latest = status
                progress = ""
                if status.progress_done is not None:
                    if status.progress_total:
                        progress = f"; прогресс: {status.progress_done}/{status.progress_total}"
                    else:
                        progress = f"; проверено: {status.progress_done}"
                print(f"Совпадений: {status.matched}/{status.loaded}{progress}", flush=True)
                continue
            parsed = parse_hashcat_match(line, mode)
            if parsed is not None:
                if match is not None:
                    output_warning = True
                else:
                    match = parsed
                continue
            possible_hash, separator, _ = line.rstrip("\r\n").rpartition(":")
            if separator and looks_like_output_hash(possible_hash, mode):
                output_warning = True
                print("Не удалось разобрать запись совпадения Hashcat; содержимое скрыто.",
                      file=sys.stderr, flush=True)
                continue
            if line.startswith(("Hashfile '", "Hash parsing error in hashfile:",
                                "Skipping invalid or unsupported rule")):
                input_warning = True
            print(line, end="", flush=True)
        returncode = process.wait()
    except KeyboardInterrupt:
        stop_process(process)
        return StageResult("interrupted", 130, latest, None, input_warning, output_warning)
    except OSError as exc:
        stop_process(process)
        raise AuditError(f"Ошибка обмена с Hashcat: {exc}") from exc
    finally:
        if process.stdout is not None:
            process.stdout.close()
        if process.stdin is not None and not process.stdin.closed:
            try:
                process.stdin.close()
            except BrokenPipeError:
                pass

    consistent_status = latest is not None and latest.loaded == 1
    if (returncode == 0 and consistent_status and latest.status_code == 6
            and latest.matched == 1 and match is not None
            and not input_warning and not output_warning):
        return StageResult("matched", returncode, latest, match, input_warning, output_warning)
    if (returncode == 1 and consistent_status and latest.status_code == 5
            and latest.matched == 0 and latest.rejected == 0 and match is None
            and not input_warning and not output_warning):
        return StageResult("exhausted", returncode, latest, None, input_warning, output_warning)
    return StageResult("incomplete", returncode, latest, None, input_warning, output_warning)


def read_target_file(path: Path) -> str:
    try:
        with path.open("r", encoding="utf-8") as stream:
            records = []
            while True:
                line = stream.readline(4098)
                if not line:
                    break
                if len(line) == 4098 and not line.endswith("\n"):
                    raise AuditError("Строка хеша слишком длинная.")
                if line.strip():
                    records.append(line.strip())
                    if len(records) > 1:
                        raise AuditError("Сценарий подсказки принимает ровно одну непустую запись хеша.")
    except UnicodeError as exc:
        raise AuditError("Файл хеша должен быть в кодировке UTF-8.") from exc
    except OSError as exc:
        raise AuditError(f"Не удалось прочитать файл хеша: {exc}") from exc
    if not records:
        raise AuditError("Файл хеша пуст.")
    return records[0]


def prompt(text: str) -> str:
    try:
        return input(text)
    except EOFError as exc:
        raise AuditError("Не получен ввод. Укажите нужные параметры в командной строке.") from exc


def select_mode(value: Optional[int]) -> int:
    if value is not None:
        return value
    while True:
        answer = prompt("Режим Hashcat (например 1000 NTLM, 0 MD5): ").strip()
        if len(answer) <= 6 and answer.isascii() and answer.isdigit() and int(answer) in HASH_MODES:
            return int(answer)
        print("Неизвестный режим. Доступные: " + ", ".join(map(str, sorted(HASH_MODES))), file=sys.stderr)


def validate_target(target: str, mode: int, username: bool) -> None:
    try:
        encoded = target.encode("utf-8")
    except UnicodeError as exc:
        raise AuditError("Целевой хеш не кодируется в UTF-8.") from exc
    if not target or len(encoded) > 4096:
        raise AuditError("Целевой хеш пуст или слишком длинный.")
    if any(ord(char) < 32 or ord(char) == 127 for char in target):
        raise AuditError("Целевой хеш не должен содержать управляющие символы или переводы строк.")
    if mode in (1000, 2100) and not looks_like_mode(encoded, mode, username):
        raise AuditError(f"Целевой хеш не соответствует синтаксису режима {mode}; проверьте --username.")
    if username and mode not in (1000, 2100):
        name, separator, value = target.partition(":")
        if not name or not separator or not value:
            raise AuditError("При --username ожидается запись имя:хеш.")


def validate_hint(hint: str) -> bytes:
    try:
        encoded = hint.encode("utf-8")
    except UnicodeError as exc:
        raise AuditError("Подсказка не кодируется в UTF-8.") from exc
    if len(encoded) > 256:
        raise AuditError("Подсказка слишком длинная: максимум 256 байт в UTF-8.")
    if any(char in hint for char in ("\r", "\n", "\x00")):
        raise AuditError("Подсказка не должна содержать NUL или перевод строки.")
    return encoded


def validate_mask(mask: str) -> None:
    try:
        encoded = mask.encode("utf-8")
    except UnicodeError as exc:
        raise AuditError("Маска не кодируется в UTF-8.") from exc
    if not mask or len(encoded) > 256 or any(ord(char) < 32 or ord(char) == 127 for char in mask):
        raise AuditError("Маска пуста, слишком длинна или содержит управляющие символы.")


def dictionary_for(root: Path, value: Optional[str]) -> tuple[Optional[Path], Optional[bytes], str]:
    # Если пользователь не передал словарь и файла по умолчанию нет, используем
    # короткий публичный список из основного приложения, не сохраняя совпадения.
    if value is None and not os.path.lexists(root / "wordlist.txt"):
        return None, ("\n".join(COMMON_PASSWORDS) + "\n").encode("ascii"), "builtin-weak"
    path = checked_input(root, "wordlist.txt" if value is None else value, "Словарь")
    if path.stat().st_size == 0:
        raise AuditError("Словарь пуст.")
    return path, None, "file"


def stage_report(label: str, result: StageResult) -> dict:
    status = result.status
    return {
        "stage": label,
        "outcome": result.outcome,
        "hashcat_exit_code": result.returncode,
        "hashcat_status_code": None if status is None else status.status_code,
        "loaded_unique_hashes": None if status is None else status.loaded,
        "matched_unique_hashes": None if status is None else status.matched,
        "progress": None if status is None else [status.progress_done, status.progress_total],
        "rejected_candidates": None if status is None else status.rejected,
        "input_warning_detected": result.input_warning,
        "output_warning_detected": result.output_warning,
    }


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Один хеш: подсказка → правила Hashcat → словарь → маска. Пароль выводится в терминал."
    )
    parser.add_argument("--usb", required=True, help="каталог данных на носителе")
    parser.add_argument("--mode", type=int, choices=sorted(HASH_MODES), help="режим Hashcat; иначе спросить")
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--hashes", help="файл с одной записью хеша внутри --usb; иначе спросить")
    target.add_argument("--target", help="хеш в аргументе (может попасть в историю команд)")
    parser.add_argument("--hint", help="подсказка; без параметра вводится скрыто, пустая строка — пропустить")
    parser.add_argument("--wordlist", help="словарь внутри --usb; по умолчанию wordlist.txt или встроенный список")
    masks = parser.add_mutually_exclusive_group()
    masks.add_argument("--mask", action="append", nargs="+", metavar="МАСКА", help="маска Hashcat, можно повторить")
    masks.add_argument("--no-mask", action="store_true", help="не спрашивать и не запускать маску")
    parser.add_argument("--runtime", type=positive_int, metavar="СЕКУНДЫ", help="лимит времени каждого этапа Hashcat")
    parser.add_argument("--cpu", action="store_true", help="использовать устройства OpenCL CPU")
    parser.add_argument("--username", action="store_true", help="запись хеша имеет префикс имя:хеш")
    parser.add_argument("--hashcat", default="hashcat", help="путь к Hashcat или имя в PATH")
    parser.add_argument("--strict", action="store_true", help="код 1, если пароль не найден")
    parser.add_argument("--save-plaintext", action="store_true",
                        help="дополнительно сохранить hash:plain в cracked.txt (чувствительный файл)")
    return parser


def crack(args: argparse.Namespace) -> int:
    root = checked_root(args.usb)
    warn_if_volatile(filesystem_type(root))
    ensure_writable(root)
    mode = select_mode(args.mode)
    source_target_path = None
    if args.hashes is not None:
        source_target_path = checked_input(root, args.hashes, "Файл хеша")
        target = read_target_file(source_target_path)
        target_source = "file"
    elif args.target is not None:
        target = args.target.strip()
        target_source = "argument"
    else:
        target = prompt("Целевой хеш: ").strip()
        target_source = "prompt"
    validate_target(target, mode, args.username)
    if args.hint is None:
        try:
            hint = getpass.getpass("Подсказка (пусто — пропустить): ")
        except (EOFError, OSError) as exc:
            raise AuditError("Не удалось получить подсказку; используйте --hint или --hint ''.") from exc
    else:
        hint = args.hint
    hint_bytes = validate_hint(hint)

    run_dir = prepare_run(root)
    started = datetime.now(timezone.utc).isoformat()
    report = {
        "schema_version": 1,
        "scenario": "hint",
        "started_utc": started,
        "hash_mode": mode,
        "target_source": target_source,
        "hint_supplied": bool(hint),
        "hashcat_version": None,
        "dictionary_source": None,
        "mask_skipped": None,
        "masks_attempted": 0,
        "attempts": [],
        "outcome": "incomplete",
        "match_stage": None,
        "password_file_saved": False,
        "run_complete": False,
        "error": None,
    }
    print(f"Результаты: {run_dir}", flush=True)
    print("При совпадении пароль будет показан в терминале; защитите его вывод.", flush=True)

    def emit_match(hash_value: str, password: bytes) -> None:
        result_line = f"{hash_value}:{password_for_terminal(password)}"
        print(result_line, flush=True)
        if args.save_plaintext:
            path = run_dir / "cracked.txt"
            descriptor = None
            try:
                flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0)
                descriptor = os.open(path, flags, 0o600)
                with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
                    descriptor = None
                    stream.write(result_line + "\n")
            except OSError:
                if descriptor is not None:
                    os.close(descriptor)
                report["password_file_saved"] = None
                print(f"Внимание: проверьте {path}; файл мог быть записан частично.",
                      file=sys.stderr, flush=True)
                raise
            report["password_file_saved"] = True
            print(f"Внимание: пароль сохранён в конфиденциальный файл {path}", flush=True)

    code = 2
    direct = None
    try:
        if hint:
            direct = compare_hint_locally(hint, target, mode, args.username)
            if direct is not None:
                report["attempts"].append({"stage": "hint-exact", "engine": "python",
                                           "outcome": "matched" if direct else "exhausted"})
                if direct:
                    emit_match(raw_hash_value(target, mode, args.username), hint_bytes)
                    report.update(outcome="matched", match_stage="hint-exact", run_complete=True)
                    code = 0
                else:
                    print("Подсказка не совпала; проверяю мутации.", flush=True)

        if code != 0:
            executable = find_hashcat(args.hashcat, root)
            report["hashcat_version"] = hashcat_version(executable, root)
            env = runtime_environment(run_dir)
            # Зафиксировать ровно ту запись, которая прошла предварительную проверку:
            # внешний файл может измениться между этапами.
            target_path = run_dir / "target-hash.txt"
            with target_path.open("x", encoding="utf-8", newline="\n") as stream:
                stream.write(target + "\n")

            def sweep(label: str, *, wordlist: Optional[Path] = None,
                      candidate_input: Optional[bytes] = None, rules: Optional[Path] = None,
                      mask: Optional[str] = None) -> str:
                session = f"usb-hint-{run_dir.name}-{len(report['attempts'])}"
                command = make_command(executable, mode, target_path, session, cpu=args.cpu,
                                       username=args.username, runtime=args.runtime,
                                       wordlist=wordlist, rules=rules, mask=mask,
                                       literal_input=label in ("hint-exact", "hint-rules"))
                print(f"Этап: {label}", flush=True)
                result = run_stage(command, root, env, session, mode, candidate_input)
                attempt = stage_report(label, result)
                if result.outcome == "matched" and result.match is not None:
                    if not raw_result_matches_target(result.match[0], target, mode, args.username):
                        attempt.update(outcome="incomplete", output_warning_detected=True)
                        report["attempts"].append(attempt)
                        print("Hashcat вернул несовпадающий хеш; дальнейшие этапы остановлены.",
                              file=sys.stderr, flush=True)
                        return "incomplete"
                report["attempts"].append(attempt)
                if result.outcome == "matched":
                    assert result.match is not None
                    hash_value, password = result.match
                    emit_match(hash_value, password)
                    report.update(outcome="matched", match_stage=label, run_complete=True)
                elif result.outcome == "interrupted":
                    report["outcome"] = "interrupted"
                elif result.outcome != "exhausted":
                    print("Этап не завершён или его результат не подтверждён; следующие этапы не запущены.",
                          file=sys.stderr, flush=True)
                return result.outcome

            stage = "exhausted"
            # Солёные/ресурсозатратные форматы сверяются по одной подсказке самим
            # Hashcat: так используются соль и параметры именно целевого хеша.
            if hint and direct is None:
                stage = sweep("hint-exact", candidate_input=hint_bytes + b"\n")
            if hint and stage == "exhausted":
                rules = hint_rules()
                rules_path = run_dir / "hint-rules.rule"
                with rules_path.open("x", encoding="ascii", newline="\n") as stream:
                    stream.write("\n".join(rules) + "\n")
                print(f"Правил мутации: {len(rules)}.", flush=True)
                stage = sweep("hint-rules", candidate_input=hint_bytes + b"\n", rules=rules_path)
            if stage == "exhausted":
                wordlist, candidate_input, source = dictionary_for(root, args.wordlist)
                if wordlist is not None and wordlist == source_target_path:
                    raise AuditError("Файл хеша и словарь должны быть разными файлами.")
                report["dictionary_source"] = source
                print("Словарь: " + ("встроенный короткий список" if wordlist is None else str(wordlist)), flush=True)
                stage = sweep("dictionary", wordlist=wordlist, candidate_input=candidate_input)
            if stage == "exhausted":
                masks = [mask for group in (args.mask or []) for mask in group]
                if args.mask is None and not args.no_mask and sys.stdin.isatty():
                    entered = prompt("Маска Hashcat (пусто — пропустить): ")
                    if entered:
                        masks.append(entered)
                if not masks:
                    report["mask_skipped"] = True
                    print("Маска не задана; этап пропущен.", flush=True)
                else:
                    report["mask_skipped"] = False
                for index, mask in enumerate(masks, start=1):
                    validate_mask(mask)
                    report["masks_attempted"] += 1
                    stage = sweep(f"mask-{index}", mask=mask)
                    if stage != "exhausted":
                        break
            if stage == "matched":
                code = 0
            elif stage == "exhausted":
                print("Пароль не найден среди проверенных кандидатов; это не доказывает его стойкость.",
                      flush=True)
                report.update(outcome="not_found", run_complete=True)
                code = 1 if args.strict else 0
            elif stage == "interrupted":
                code = 130
            else:
                code = 2
    except KeyboardInterrupt:
        report["outcome"] = "interrupted"
        print("\nПроверка прервана пользователем.", file=sys.stderr)
        code = 130
    except (AuditError, OSError) as exc:
        # Текст ошибки может содержать пути пользователя; в отчёт его не копируем.
        report["error"] = "preparation_or_io_error"
        print(f"Ошибка: {exc}", file=sys.stderr)
        code = 2

    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    try:
        (run_dir / "report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        raise AuditError(f"Не удалось сохранить отчёт: {exc}") from exc
    print(f"Отчёт: {run_dir / 'report.json'}", flush=True)
    return code


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    old_umask = os.umask(0o077)
    try:
        return crack(args)
    except KeyboardInterrupt:
        print("\nПроверка прервана пользователем.", file=sys.stderr)
        return 130
    except (AuditError, OSError) as exc:
        print(f"Ошибка: {exc}", file=sys.stderr)
        return 2
    finally:
        os.umask(old_umask)


if __name__ == "__main__":
    sys.exit(main())
