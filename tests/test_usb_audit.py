import contextlib
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import usb_audit


NTLM_EXAMPLE = "0123456789abcdef0123456789ABCDEF"
DCC2_EXAMPLE = f"$DCC2$10240#alice#{NTLM_EXAMPLE}"


class FakeProcess:
    def __init__(self, output, returncode):
        self.stdout = io.StringIO(output)
        self.returncode = returncode
        self.terminated = False
        self.killed = False

    def wait(self, timeout=None):
        return self.returncode

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "USB with spaces"
        self.root.mkdir()
        self.hashes = self.root / "hashes.txt"
        self.wordlist = self.root / "wordlist.txt"
        self.hashes.write_text("hash-a\nhash-b\n", encoding="utf-8")
        self.wordlist.write_text("candidate-secret\nother\n", encoding="utf-8")
        self.args = ["--usb", str(self.root), "--mode", "0", "--hashcat", sys.executable]

    def run_audit(self, returncode=1, status_code=5, matched=1, loaded=2,
                  output_lines=("hash-a",), extra_args=(), rejected=0,
                  raw_output=None, prefix_output="", spawn_error=None, match_pairs=()):
        calls = []

        def fake_popen(command, **kwargs):
            calls.append((command, kwargs))
            if spawn_error is not None:
                raise spawn_error
            if "--outfile" in command:
                outfile = Path(command[command.index("--outfile") + 1])
                outfile.write_text("".join(line + "\n" for line in output_lines), encoding="utf-8")
            session = command[command.index("--session") + 1]
            output = raw_output
            if output is None:
                match_output = "".join(f"{value}:{password.encode('ascii').hex()}\n"
                                       for value, password in match_pairs)
                output = prefix_output + match_output + json.dumps({
                    "session": session,
                    "status": status_code,
                    "recovered_hashes": [matched, loaded],
                    "progress": [2, 2],
                    "rejected": rejected,
                    "target": "sensitive target",
                }) + "\n"
            return FakeProcess(output, returncode)

        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(usb_audit, "hashcat_version", return_value="v6.2.6"), \
                mock.patch.object(usb_audit, "filesystem_type", return_value="ext4"), \
                mock.patch.object(usb_audit.subprocess, "Popen", side_effect=fake_popen), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = usb_audit.main(self.args + list(extra_args))
        reports = sorted(self.root.glob("audit-results/*/report.json"))
        return result, stdout.getvalue(), stderr.getvalue(), calls, reports

    def read_report(self, reports):
        self.assertTrue(reports)
        return json.loads(reports[-1].read_text(encoding="utf-8"))

    def test_exhausted_is_success_with_no_plaintext_in_output(self):
        before_hashes = self.hashes.read_bytes()
        before_words = self.wordlist.read_bytes()
        code, out, err, calls, reports = self.run_audit()
        report = self.read_report(reports)
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertTrue(report["run_complete"])
        self.assertEqual(report["outcome"], "dictionary_exhausted")
        self.assertEqual(report["hashcat_exit_code"], 1)
        self.assertEqual((report["matched_unique_hashes"], report["loaded_unique_hashes"]), (1, 2))
        self.assertTrue(report["matched_file_consistent"])
        self.assertEqual((reports[-1].parent / "matched-hashes.txt").read_text(), "hash-a\n")
        self.assertNotIn("candidate-secret", reports[-1].read_text())
        self.assertNotIn("candidate-secret", out)
        self.assertNotIn("sensitive target", out)
        self.assertEqual(self.hashes.read_bytes(), before_hashes)
        self.assertEqual(self.wordlist.read_bytes(), before_words)
        self.assertEqual(len(calls), 1)

    def test_hashcat_arguments_and_runtime_are_confined(self):
        code, _, _, calls, reports = self.run_audit(
            extra_args=("--username", "--cpu", "--runtime", "20")
        )
        self.assertEqual(code, 0)
        command, kwargs = calls[0]
        self.assertEqual(kwargs["cwd"], self.root.resolve())
        self.assertNotIn("shell", kwargs)
        self.assertEqual(command[command.index("--hash-type") + 1], "0")
        self.assertEqual(command[command.index("--attack-mode") + 1], "0")
        self.assertEqual(command[command.index("--outfile-format") + 1], "1")
        self.assertEqual(command[command.index("--opencl-device-types") + 1], "1")
        self.assertEqual(command[command.index("--runtime") + 1], "20")
        self.assertIn("--username", command)
        for flag in ("--potfile-disable", "--logfile-disable", "--restore-disable"):
            self.assertIn(flag, command)
        self.assertEqual(command[-2:], [self.hashes.as_posix(), self.wordlist.as_posix()])
        self.assertTrue(Path(kwargs["env"]["XDG_CACHE_HOME"]).is_relative_to(reports[-1].parent))
        self.assertTrue(Path(kwargs["env"]["TMPDIR"]).is_relative_to(reports[-1].parent))
        self.assertEqual(self.read_report(reports)["runtime_limit_seconds"], 20)

    def test_builtin_weak_list_needs_no_wordlist_and_keeps_passwords_hidden(self):
        self.wordlist.unlink()
        code, out, err, calls, reports = self.run_audit(extra_args=("--weak",))
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertNotIn("1111", out)
        command, _ = calls[0]
        self.assertIn("--outfile", command)
        self.assertEqual(command[command.index("--outfile-format") + 1], "1")
        report = self.read_report(reports)
        self.assertEqual(report["candidate_source"], "builtin-weak")
        self.assertFalse(report["passwords_shown_in_terminal"])
        candidates = reports[-1].parent / "weak-candidates.txt"
        self.assertEqual(candidates.read_text(encoding="ascii").splitlines(), list(usb_audit.COMMON_PASSWORDS))
        self.assertEqual(command[-1], candidates.as_posix())

    def test_builtin_weak_reveals_match_but_saves_only_hash(self):
        self.wordlist.unlink()
        self.hashes.write_text(NTLM_EXAMPLE + "\n", encoding="utf-8")
        code, out, err, calls, reports = self.run_audit(
            returncode=0, status_code=6, matched=1, loaded=1,
            extra_args=("--mode", "1000", "--weak", "--show-passwords"),
            match_pairs=((NTLM_EXAMPLE, "1111"),),
        )
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertIn('Слабый пароль: "1111"', out)
        self.assertIn(NTLM_EXAMPLE, out)
        command, _ = calls[0]
        self.assertNotIn("--outfile", command)
        self.assertEqual(command[command.index("--outfile-format") + 1], "1,3")
        self.assertIn("--potfile-disable", command)
        report = self.read_report(reports)
        self.assertTrue(report["run_complete"])
        self.assertTrue(report["passwords_shown_in_terminal"])
        self.assertNotIn('"1111"', reports[-1].read_text(encoding="utf-8"))
        self.assertEqual((reports[-1].parent / "matched-hashes.txt").read_text(), NTLM_EXAMPLE + "\n")

    def test_builtin_weak_detects_missing_streamed_matches(self):
        self.hashes.write_text(NTLM_EXAMPLE + "\n", encoding="utf-8")
        code, _, err, _, reports = self.run_audit(
            returncode=0, status_code=6, matched=1, loaded=1,
            extra_args=("--mode", "1000", "--weak", "--show-passwords"),
            match_pairs=(),
        )
        self.assertEqual(code, 2)
        self.assertIn("не совпадает", err)
        report = self.read_report(reports)
        self.assertFalse(report["matched_file_consistent"])
        self.assertFalse(report["run_complete"])

    def test_builtin_weak_reveals_dcc2_and_respects_username(self):
        self.wordlist.unlink()
        self.hashes.write_text(f"alice:{DCC2_EXAMPLE}\n", encoding="utf-8")
        code, out, _, _, reports = self.run_audit(
            returncode=0, status_code=6, matched=1, loaded=1,
            extra_args=("--mode", "2100", "--weak", "--show-passwords", "--username"),
            match_pairs=((DCC2_EXAMPLE, "12345"),),
        )
        self.assertEqual(code, 0)
        self.assertIn('Слабый пароль: "12345"', out)
        self.assertEqual((reports[-1].parent / "matched-hashes.txt").read_text(), DCC2_EXAMPLE + "\n")

    def test_unrecognized_match_is_hidden_and_marks_report_incomplete(self):
        self.hashes.write_text(NTLM_EXAMPLE + "\n", encoding="utf-8")
        code, out, err, _, reports = self.run_audit(
            returncode=1, status_code=5, matched=0, loaded=1,
            extra_args=("--mode", "1000", "--weak", "--show-passwords"),
            match_pairs=((NTLM_EXAMPLE, "not-in-built-in-list"),),
        )
        self.assertEqual(code, 2)
        self.assertNotIn("not-in-built-in-list", out)
        self.assertNotIn("not-in-built-in-list".encode("ascii").hex(), out)
        self.assertIn("содержимое скрыто", err)
        report = self.read_report(reports)
        self.assertTrue(report["output_warning_detected"])
        self.assertFalse(report["run_complete"])

    def test_all_loaded_hashes_found(self):
        code, out, _, _, reports = self.run_audit(
            returncode=0, status_code=6, matched=2, output_lines=("hash-a", "hash-b")
        )
        self.assertEqual(code, 0)
        self.assertIn("всех загруженных хешей", out)
        self.assertEqual(self.read_report(reports)["outcome"], "all_loaded_hashes_matched")

    def test_no_matches_is_still_a_complete_audit(self):
        code, _, _, _, reports = self.run_audit(matched=0, output_lines=())
        self.assertEqual(code, 0)
        report = self.read_report(reports)
        self.assertEqual(report["matched_unique_hashes"], 0)
        self.assertEqual(report["matched_file_lines"], 0)
        self.assertTrue(report["run_complete"])

    def test_time_limit_is_incomplete(self):
        code, _, err, _, reports = self.run_audit(returncode=4, status_code=11)
        report = self.read_report(reports)
        self.assertEqual(code, 2)
        self.assertEqual(report["outcome"], "interrupted")
        self.assertFalse(report["run_complete"])
        self.assertIn("не завершена", err)

    def test_partial_status_is_not_mistaken_for_final_status(self):
        code, _, err, _, reports = self.run_audit(returncode=1, status_code=3)
        self.assertEqual(code, 2)
        self.assertFalse(self.read_report(reports)["run_complete"])
        self.assertIn("итогового статуса", err)

    def test_missing_status_is_not_reported_as_zero(self):
        code, _, err, _, reports = self.run_audit(raw_output="Hashcat failed\n", returncode=255)
        report = self.read_report(reports)
        self.assertEqual(code, 2)
        self.assertIsNone(report["matched_unique_hashes"])
        self.assertIsNone(report["loaded_unique_hashes"])
        self.assertEqual(report["outcome"], "error")
        self.assertIn("счётчики", err)

    def test_mismatching_outfile_is_not_successful(self):
        code, _, err, _, reports = self.run_audit(matched=2, output_lines=("hash-a",))
        report = self.read_report(reports)
        self.assertEqual(code, 2)
        self.assertFalse(report["matched_file_consistent"])
        self.assertFalse(report["run_complete"])
        self.assertIn("не совпадает", err)

    def test_rejected_candidates_make_the_audit_incomplete(self):
        code, out, _, _, reports = self.run_audit(rejected=3)
        report = self.read_report(reports)
        self.assertEqual(code, 2)
        self.assertEqual(report["rejected_candidates"], 3)
        self.assertFalse(report["run_complete"])
        self.assertIn("отклонил кандидатов: 3", out)

    def test_input_format_warnings_make_the_audit_incomplete(self):
        for warning in ("Hashfile 'file' on line 1 (bad): Token length exception\n",
                        "Hash parsing error in hashfile: 'file' on line 1 (bad): error\n"):
            with self.subTest(warning=warning):
                code, _, err, _, reports = self.run_audit(prefix_output=warning)
                # Выбираем отчёт по моменту записи, а не случайному суффиксу.
                report_file = max(reports, key=lambda p: p.stat().st_mtime_ns)
                report = json.loads(report_file.read_text(encoding="utf-8"))
                self.assertEqual(code, 2)
                self.assertTrue(report["input_warning_detected"])
                self.assertFalse(report["run_complete"])
                self.assertIn("проблемах со входным файлом", err)

    def test_duplicates_or_skipped_hashes_are_not_counted_as_accounts(self):
        self.hashes.write_text("hash-a\nhash-a\n\nhash-b\n", encoding="utf-8")
        code, out, _, _, reports = self.run_audit()
        self.assertEqual(code, 0)
        self.assertEqual(self.read_report(reports)["input_nonempty_lines"], 3)
        self.assertIn("возможны дубликаты или ошибки формата", out)

    def test_mixed_hash_types_after_first_five_are_rejected_before_launch(self):
        self.hashes.write_text((NTLM_EXAMPLE + "\n") * 6 + DCC2_EXAMPLE + "\n", encoding="utf-8")
        code, _, err, calls, reports = self.run_audit(extra_args=("--mode", "1000"))
        self.assertEqual(code, 2)
        self.assertIn("Строка 7", err)
        self.assertIn("режима 1000", err)
        self.assertNotIn(DCC2_EXAMPLE, err)
        self.assertFalse(calls)
        self.assertFalse(reports)

    def test_first_blank_lines_do_not_bypass_validation(self):
        self.hashes.write_text("\n" * 6 + "not-a-hash\n", encoding="utf-8")
        code, _, err, calls, reports = self.run_audit(extra_args=("--mode", "1000"))
        self.assertEqual(code, 2)
        self.assertIn("Строка 7", err)
        self.assertNotIn("not-a-hash", err)
        self.assertFalse(calls)
        self.assertFalse(reports)

    def test_username_prefix_is_respected_for_ntlm_and_dcc2(self):
        cases = (("1000", NTLM_EXAMPLE), ("2100", DCC2_EXAMPLE))
        for mode, digest in cases:
            with self.subTest(mode=mode):
                self.hashes.write_text(f"alice:{digest}\n", encoding="utf-8")
                code, _, _, calls, reports = self.run_audit(extra_args=("--mode", mode, "--username"))
                self.assertEqual(code, 0)
                self.assertTrue(calls)
                self.assertTrue(reports)
                code, _, err, calls, _ = self.run_audit(extra_args=("--mode", mode))
                self.assertEqual(code, 2)
                self.assertIn("--username", err)
                self.assertFalse(calls)

    def test_process_launch_error_produces_incomplete_report(self):
        code, _, err, _, reports = self.run_audit(spawn_error=FileNotFoundError("gone"))
        report = self.read_report(reports)
        self.assertEqual(code, 2)
        self.assertEqual(report["outcome"], "error")
        self.assertIn("Не удалось запустить Hashcat", report["error"])
        self.assertIn("Не удалось запустить Hashcat", err)

    def test_new_run_directory_and_posix_permissions(self):
        first = self.run_audit()[-1]
        second = self.run_audit()[-1]
        self.assertEqual(len(first), 1)
        self.assertEqual(len(second), 2)
        self.assertNotEqual(second[0].parent, second[1].parent)
        if os.name != "nt":
            for path in second:
                self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_missing_or_empty_input_rejected_before_launch(self):
        self.wordlist.unlink()
        code, _, err, calls, reports = self.run_audit()
        self.assertEqual(code, 2)
        self.assertIn("Словарь недоступен", err)
        self.assertFalse(calls)
        self.assertFalse(reports)
        self.wordlist.write_text("", encoding="utf-8")
        code, _, err, calls, _ = self.run_audit()
        self.assertEqual(code, 2)
        self.assertIn("Словарь пуст", err)
        self.assertFalse(calls)
        self.wordlist.write_text("word\n", encoding="utf-8")
        self.hashes.write_text(" \n\n", encoding="utf-8")
        code, _, err, calls, _ = self.run_audit()
        self.assertEqual(code, 2)
        self.assertIn("непустых строк", err)
        self.assertFalse(calls)

    def test_same_file_rejected(self):
        code, _, err, calls, _ = self.run_audit(extra_args=("--wordlist", "hashes.txt"))
        self.assertEqual(code, 2)
        self.assertIn("разными файлами", err)
        self.assertFalse(calls)

    def test_input_cannot_escape_usb_even_via_symlink(self):
        outside = Path(self.temp.name) / "outside.txt"
        outside.write_text("hash\n", encoding="utf-8")
        code, _, err, calls, _ = self.run_audit(extra_args=("--hashes", str(outside)))
        self.assertEqual(code, 2)
        self.assertIn("внутри указанного носителя", err)
        self.assertFalse(calls)
        try:
            (self.root / "link.txt").symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("symbolic links unavailable")
        code, _, err, calls, _ = self.run_audit(extra_args=("--hashes", "link.txt"))
        self.assertEqual(code, 2)
        self.assertIn("внутри указанного носителя", err)
        self.assertFalse(calls)

    def test_results_symlink_outside_usb_rejected(self):
        outside = Path(self.temp.name) / "outside-results"
        outside.mkdir()
        try:
            (self.root / "audit-results").symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symbolic links unavailable")
        code, _, err, calls, reports = self.run_audit()
        self.assertEqual(code, 2)
        self.assertIn("за пределы носителя", err)
        self.assertFalse(calls)
        self.assertFalse(reports)
        self.assertFalse(list(outside.iterdir()))

    def test_reveal_interrupt_preserves_hash_only_and_marks_incomplete(self):
        self.hashes.write_text(NTLM_EXAMPLE + "\n", encoding="utf-8")

        class InterruptAfterMatch:
            def __iter__(self):
                yield NTLM_EXAMPLE + ":31313131\n"
                raise KeyboardInterrupt

            def close(self):
                pass

        process = FakeProcess("", 130)
        process.stdout = InterruptAfterMatch()
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(usb_audit, "hashcat_version", return_value="v6.2.6"), \
                mock.patch.object(usb_audit, "filesystem_type", return_value="ext4"), \
                mock.patch.object(usb_audit.subprocess, "Popen", return_value=process), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = usb_audit.main(self.args + ["--mode", "1000", "--weak", "--show-passwords"])
        self.assertEqual(code, 130)
        self.assertIn('Слабый пароль: "1111"', out.getvalue())
        self.assertTrue(process.terminated)
        reports = list((self.root / "audit-results").glob("*/report.json"))
        report = self.read_report(reports)
        self.assertFalse(report["run_complete"])
        self.assertEqual(report["matched_file_lines"], 1)
        self.assertEqual((reports[-1].parent / "matched-hashes.txt").read_text(), NTLM_EXAMPLE + "\n")

    def test_keyboard_interrupt_creates_incomplete_report(self):
        class InterruptingStream:
            def __iter__(self):
                raise KeyboardInterrupt

            def close(self):
                pass

        process = FakeProcess("", 130)
        process.stdout = InterruptingStream()
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(usb_audit, "hashcat_version", return_value="v6.2.6"), \
                mock.patch.object(usb_audit, "filesystem_type", return_value="ext4"), \
                mock.patch.object(usb_audit.subprocess, "Popen", return_value=process), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = usb_audit.main(self.args)
        report = self.read_report(list(self.root.glob("audit-results/*/report.json")))
        self.assertEqual(code, 130)
        self.assertTrue(process.terminated)
        self.assertEqual(report["outcome"], "interrupted")
        self.assertFalse(report["run_complete"])
        self.assertIn("прервана", stderr.getvalue())

    def test_check_needs_no_hashes_or_mode_and_warns_about_live_overlay(self):
        self.hashes.unlink()
        self.wordlist.unlink()
        stdout, stderr = io.StringIO(), io.StringIO()
        args = ["--usb", str(self.root), "--check", "--hashcat", sys.executable]
        with mock.patch.object(usb_audit, "filesystem_type", return_value="overlay"), \
                mock.patch.object(usb_audit, "hashcat_version", return_value="v6.2.6"), \
                mock.patch.object(usb_audit, "run_hashcat") as run_hashcat, \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = usb_audit.main(args)
        self.assertEqual(code, 0)
        self.assertIn("Запись: доступна", stdout.getvalue())
        self.assertIn("Хеши и словарь не обрабатывались", stdout.getvalue())
        self.assertIn("Сохранность после перезагрузки не проверена", stdout.getvalue())
        self.assertIn("persistence", stderr.getvalue())
        self.assertEqual(list(self.root.iterdir()), [])
        run_hashcat.assert_not_called()

    def test_check_rejects_read_only_data_partition(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        args = ["--usb", str(self.root), "--check", "--hashcat", sys.executable]
        with mock.patch.object(usb_audit, "filesystem_type", return_value="iso9660"), \
                mock.patch.object(usb_audit.tempfile, "TemporaryFile", side_effect=OSError("read-only")), \
                mock.patch.object(usb_audit, "hashcat_version") as version, \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = usb_audit.main(args)
        self.assertEqual(code, 2)
        self.assertIn("недоступен для записи", stderr.getvalue())
        self.assertIn("read-only", stderr.getvalue())
        self.assertFalse((self.root / "audit-results").exists())
        version.assert_not_called()

    def test_normal_run_rejects_unwritable_storage(self):
        with mock.patch.object(usb_audit.tempfile, "TemporaryFile", side_effect=OSError("read-only")):
            code, _, err, calls, reports = self.run_audit()
        self.assertEqual(code, 2)
        self.assertIn("недоступен для записи", err)
        self.assertFalse(calls)
        self.assertFalse(reports)

    def test_mode_is_required_for_audit_but_not_check(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as exc:
            usb_audit.main(["--usb", str(self.root)])
        self.assertEqual(exc.exception.code, 2)

    def test_weak_options_reject_ambiguous_or_unexpected_use(self):
        for extra in (("--show-passwords",), ("--weak", "--wordlist", "other.txt")):
            with self.subTest(extra=extra), contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit) as exc:
                usb_audit.main(self.args + list(extra))
            self.assertEqual(exc.exception.code, 2)
            self.assertFalse((self.root / "audit-results").exists())

    @unittest.skipIf(os.name == "nt", "portable fake executable uses a POSIX shebang")
    def test_cli_end_to_end_with_simulated_hashcat(self):
        fake = self.root / "fake-hashcat"
        fake.write_text(
            "#!/usr/bin/env python3\n"
            "import json, pathlib, sys\n"
            "if '--version' in sys.argv:\n"
            "    print('v6.2.6')\n"
            "    sys.exit(0)\n"
            "args = sys.argv[1:]\n"
            "out = pathlib.Path(args[args.index('--outfile') + 1])\n"
            "out.write_text('hash-a\\n')\n"
            "session = args[args.index('--session') + 1]\n"
            "print(json.dumps({'session': session, 'status': 5, "
            "'recovered_hashes': [1, 2], 'progress': [2, 2], 'rejected': 0}))\n"
            "sys.exit(1)\n",
            encoding="utf-8",
        )
        fake.chmod(0o755)
        check = subprocess.run(
            [sys.executable, str(Path(usb_audit.__file__).resolve()), "--usb", str(self.root),
             "--check", "--hashcat", str(fake)],
            text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertIn("Хеши и словарь не обрабатывались", check.stdout)
        self.assertFalse((self.root / "audit-results").exists())
        result = subprocess.run(
            [sys.executable, str(Path(usb_audit.__file__).resolve()), "--usb", str(self.root),
             "--mode", "0", "--hashcat", str(fake)],
            text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Совпадений: 1/2", result.stdout)
        self.assertTrue(self.read_report(list(self.root.glob("audit-results/*/report.json")))["run_complete"])


class ParsingTests(unittest.TestCase):
    def test_builtin_candidates_include_requested_examples_and_are_safe_to_parse(self):
        self.assertTrue({"1111", "12345", "00000", "123456789", "13243546"}
                        .issubset(usb_audit.COMMON_PASSWORDS))
        self.assertEqual(len(usb_audit.COMMON_PASSWORDS), len(set(usb_audit.COMMON_PASSWORDS)))
        for password in usb_audit.COMMON_PASSWORDS:
            self.assertTrue(password and password.isascii())
            self.assertNotIn(":", password)
            self.assertNotIn("\n", password)
            self.assertNotIn("\r", password)

    def test_weak_match_parser_requires_expected_hash_and_candidate(self):
        hex_password = "1111".encode("ascii").hex()
        cases = {
            0: "a" * 32, 100: "a" * 40, 1000: NTLM_EXAMPLE,
            1400: "a" * 64, 1700: "a" * 128, 2100: DCC2_EXAMPLE,
            500: "$1$salt$hash", 1800: "$6$salt$hash", 7400: "$5$salt$hash",
            3200: "$2b$12$hash",
        }
        for mode, hash_value in cases.items():
            with self.subTest(mode=mode):
                line = f"{hash_value}:{hex_password}\n"
                self.assertEqual(usb_audit.parse_weak_match(line, mode), (hash_value, "1111"))
        self.assertIsNone(usb_audit.parse_weak_match(f"invalid:{hex_password}", 1000))
        self.assertIsNone(usb_audit.parse_weak_match(f"{NTLM_EXAMPLE}:not-hex", 1000))
        self.assertIsNone(usb_audit.parse_weak_match(f"{NTLM_EXAMPLE}:70726976617465", 1000))
        self.assertIsNone(usb_audit.parse_weak_match(f"{NTLM_EXAMPLE}:ff", 1000))
        self.assertIsNone(usb_audit.parse_weak_match(f"{NTLM_EXAMPLE}:" + "61" * 100, 1000))
        self.assertFalse(usb_audit.looks_like_output_hash("\x1b[31m" + NTLM_EXAMPLE, 1000))
        self.assertTrue(usb_audit.looks_like_output_hash("alice:" + NTLM_EXAMPLE, 1000))
        self.assertTrue(usb_audit.looks_like_output_hash("alice:" + DCC2_EXAMPLE, 2100))

    def test_ntlm_syntax_and_pwdump(self):
        digest = NTLM_EXAMPLE.encode("ascii")
        pwdump = b"alice:1001:" + b"a" * 32 + b":" + digest + b":::"
        self.assertTrue(usb_audit.looks_like_mode(digest + b"\r\n", 1000))
        self.assertTrue(usb_audit.looks_like_mode(b"alice:" + digest, 1000, username=True))
        self.assertTrue(usb_audit.looks_like_mode(pwdump, 1000))
        self.assertTrue(usb_audit.looks_like_mode(pwdump, 1000, username=True))
        for line, username in ((digest, True), (b":" + digest, True),
                               (b"alice:" + digest, False), (b"g" * 32, False),
                               (digest[:-1], False), (DCC2_EXAMPLE.encode(), False)):
            with self.subTest(line=line, username=username):
                self.assertFalse(usb_audit.looks_like_mode(line, 1000, username))
        # Совпадение синтаксиса не доказывает, что это NTLM, а не MD5.
        self.assertTrue(usb_audit.looks_like_mode(b"a" * 32, 1000))

    def test_dcc2_checks_structure_username_and_digest(self):
        digest = NTLM_EXAMPLE.encode("ascii")
        canonical = b"$DCC2$10240#alice#" + digest
        self.assertTrue(usb_audit.looks_like_mode(canonical, 2100))
        self.assertTrue(usb_audit.looks_like_mode(b"alice:" + canonical, 2100, username=True))
        self.assertTrue(usb_audit.looks_like_mode(b"$DCC2$1#name#part#" + digest, 2100))
        invalid = [b"$DCC2$", b"$DCC2$abc#alice#" + digest,
                   b"$DCC2$0#alice#" + digest, b"$DCC2$1000000#alice#" + digest,
                   b"$DCC2$10240#alice#" + b"z" * 32,
                   b"$DCC2$10240#alice#" + digest[:-1],
                   b"$DCC2$10240#" + b"a" * 257 + b"#" + digest,
                   digest, b"alice:" + canonical]
        for line in invalid:
            with self.subTest(line=line):
                self.assertFalse(usb_audit.looks_like_mode(line, 2100))
        self.assertFalse(usb_audit.looks_like_mode(canonical, 2100, username=True))
        self.assertTrue(usb_audit.looks_like_mode(b"anything", 0))

    def test_hash_format_streaming_counts_nonempty_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hashes.txt"
            path.write_text(f"\n{NTLM_EXAMPLE}\n\n{NTLM_EXAMPLE}\n", encoding="utf-8")
            self.assertEqual(usb_audit.validate_hashes(path, 1000, False), 2)
            path.write_text("not-validated-for-other-modes\n", encoding="utf-8")
            self.assertEqual(usb_audit.validate_hashes(path, 0, False), 1)

    def test_findmnt_detection_is_non_destructive_and_handles_failure(self):
        result = SimpleNamespace(stdout="overlay\n", returncode=0)
        with mock.patch.object(usb_audit.sys, "platform", "linux"), \
                mock.patch.object(usb_audit.shutil, "which", return_value="/usr/bin/findmnt"), \
                mock.patch.object(usb_audit.subprocess, "run", return_value=result) as run:
            self.assertEqual(usb_audit.filesystem_type(Path("/tmp/example with spaces")), "overlay")
            self.assertEqual(run.call_args.args[0][4], "/tmp/example with spaces")
            self.assertNotIn("shell", run.call_args.kwargs)
            result.stdout = "overlay\nother\n"
            self.assertIsNone(usb_audit.filesystem_type(Path("/tmp")))
            result.stdout = "ext4\n"
            result.returncode = 1
            self.assertIsNone(usb_audit.filesystem_type(Path("/tmp")))

    def test_volatile_storage_warnings_are_specific(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            usb_audit.warn_if_volatile("tmpfs")
            usb_audit.warn_if_volatile("overlay")
            usb_audit.warn_if_volatile("ext4")
        self.assertIn("tmpfs", stderr.getvalue())
        self.assertIn("persistence", stderr.getvalue())
        self.assertNotIn("ext4", stderr.getvalue())

    def test_status_validation(self):
        base = {"session": "s", "status": 5, "recovered_hashes": [1, 2],
                "progress": [10, 20], "rejected": 3}
        status = usb_audit.parse_status(json.dumps(base), "s")
        self.assertEqual((status.status_code, status.matched, status.loaded, status.rejected), (5, 1, 2, 3))
        self.assertIsNone(usb_audit.parse_status(json.dumps(base), "another"))
        self.assertIsNone(usb_audit.parse_status("not-json", "s"))
        for bad in ([3, 2], [-1, 2], [True, 2], [1], "1/2"):
            self.assertIsNone(usb_audit.parse_status(json.dumps({**base, "recovered_hashes": bad}), "s"))
        self.assertIsNone(usb_audit.parse_status(json.dumps({**base, "status": None}), "s"))

    def test_hashcat_version_validation(self):
        def version(output, rc=0):
            result = SimpleNamespace(stdout=output, stderr="", returncode=rc)
            with mock.patch.object(usb_audit.subprocess, "run", return_value=result):
                return usb_audit.hashcat_version(Path(sys.executable), Path.cwd())

        self.assertEqual(version("v6.2.6\n"), "v6.2.6")
        self.assertEqual(version("v8.0.0\n"), "v8.0.0")
        for output, rc in (("v6.2.5", 0), ("unknown", 0), ("v6.2.6", 1)):
            with self.assertRaises(usb_audit.AuditError):
                version(output, rc)

    def test_only_supported_modes_and_positive_runtime(self):
        parser = usb_audit.make_parser()
        for extra in (("--mode", "9710"), ("--mode", "0", "--runtime", "0")):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                parser.parse_args(["--usb", "/tmp", *extra])


if __name__ == "__main__":
    unittest.main()
