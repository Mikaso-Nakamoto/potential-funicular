import contextlib
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import crack_with_hint as hint
import usb_audit


def stage(outcome, hash_value=None, password=b"value"):
    if outcome == "matched":
        return hint.StageResult("matched", 0, usb_audit.HashcatStatus(6, 1, 1, 1, 1, 0),
                                (hash_value, password))
    if outcome == "exhausted":
        return hint.StageResult("exhausted", 1, usb_audit.HashcatStatus(5, 0, 1, 1, 1, 0), None)
    if outcome == "interrupted":
        return hint.StageResult("interrupted", 130, None, None)
    return hint.StageResult("incomplete", 4, usb_audit.HashcatStatus(5, 0, 1, 1, 1, 0), None)


def status_line(session, code, matched, loaded=1, rejected=0):
    return (json.dumps({"session": session, "status": code,
                        "recovered_hashes": [matched, loaded], "progress": [1, 1],
                        "rejected": rejected}) + "\n").encode()


class CapturePipe(io.BytesIO):
    def __init__(self):
        super().__init__()
        self.captured = b""

    def close(self):
        if not self.closed:
            self.captured = self.getvalue()
        super().close()


class ByteProcess:
    def __init__(self, output, returncode=0, stdin=True):
        self.stdin = CapturePipe() if stdin else None
        self.stdout = io.BytesIO(output)
        self.returncode = returncode
        self.terminated = False
        self.killed = False

    def wait(self, timeout=None):
        return self.returncode

    def poll(self):
        return None

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True


class HashAndRulesTests(unittest.TestCase):
    def test_md4_rfc_vectors_and_multiblock(self):
        vectors = {
            b"": "31d6cfe0d16ae931b73c59d7e0c089c0",
            b"a": "bde52cb31de33e46245e05fbdbd6fb24",
            b"abc": "a448017aaf21d8525fc10ae87aa6729d",
            b"message digest": "d9130a8164549fe818874806e1c7014b",
            b"abcdefghijklmnopqrstuvwxyz": "d79e1c308aa5bbcdeea8ed63df412da9",
            b"x" * 1000: "4b4cacfefc79bf951c60620df38532dc",
        }
        for value, digest in vectors.items():
            with self.subTest(value=value):
                self.assertEqual(hint.md4_digest(value).hex(), digest)
        self.assertEqual(hint.md4_digest("пароль".encode("utf-16-le")).hex(),
                         "507e3ee80df7db7c1fdd8d50ae8db606")

    def test_direct_raw_comparison_is_exact_and_case_sensitive_for_plaintext(self):
        for mode, algorithm in ((0, "md5"), (100, "sha1"), (1400, "sha256"), (1700, "sha512")):
            digest = hashlib.new(algorithm, "  A:b ".encode()).hexdigest()
            with self.subTest(mode=mode):
                self.assertTrue(hint.compare_hint_locally("  A:b ", digest.upper(), mode, False))
                self.assertFalse(hint.compare_hint_locally("a:b", digest, mode, False))
                self.assertTrue(hint.compare_hint_locally("  A:b ", "alice:" + digest, mode, True))
        self.assertIsNone(hint.compare_hint_locally("x", "bad-target", 0, False))
        self.assertIsNone(hint.compare_hint_locally("x", "$1$salt$hash", 500, False))
        self.assertIsNone(hint.compare_hint_locally("x", "$DCC2$10240#u#" + "a" * 32, 2100, False))

    def test_ntlm_username_pwdump_and_unicode(self):
        nt = hint.md4_digest("пароль".encode("utf-16-le")).hex()
        pwdump = "alice:1001:" + "a" * 32 + ":" + nt + ":::"
        for target, username in ((nt, False), ("alice:" + nt, True), (pwdump, False), (pwdump, True)):
            with self.subTest(target=target, username=username):
                self.assertTrue(hint.compare_hint_locally("пароль", target, 1000, username))
                self.assertFalse(hint.compare_hint_locally("Пароль", target, 1000, username))
                self.assertEqual(hint.raw_hash_value(target, 1000, username), nt)

    def test_rules_are_bounded_deterministic_and_cover_combined_mutations(self):
        rules = hint.hint_rules()
        self.assertEqual(rules, hint.hint_rules())
        self.assertEqual(len(rules), len(set(rules)))
        self.assertLess(len(rules), 2000)
        self.assertIn(":", rules)
        self.assertIn("c$2$0$2$4$!", rules)  # summer -> Summer2024!
        self.assertIn("se3sE3$1$2$3$!", rules)  # test -> t3st123!
        self.assertIn("l$1$2$3", rules)
        self.assertIn("u$!", rules)
        self.assertIn("$$", rules)  # literal dollar suffix
        self.assertIn("^!", rules)

    def test_hashcat_result_parsing_handles_colons_empty_and_binary_passwords(self):
        digest = "a" * 32
        self.assertEqual(hint.parse_hashcat_match(digest + ":613a62\n", 0), (digest, b"a:b"))
        self.assertEqual(hint.parse_hashcat_match(digest + ":\n", 0), (digest, b""))
        salted = "$DCC2$10240#user:domain#" + "a" * 32
        self.assertEqual(hint.parse_hashcat_match(salted + ":6162\n", 2100), (salted, b"ab"))
        self.assertIsNone(hint.parse_hashcat_match(digest + ":not-hex", 0))
        self.assertIsNone(hint.parse_hashcat_match("invalid:6162", 0))
        self.assertIsNone(hint.parse_hashcat_match(digest + ":" + "ab" * 1025, 0))
        self.assertEqual(hint.password_for_terminal(b"p:a"), "p:a")
        self.assertEqual(hint.password_for_terminal(b"\xff\n"), "$HEX[ff0a]")
        self.assertEqual(hint.password_for_terminal(b"$HEX[61]"), "$HEX[244845585b36315d]")
        self.assertTrue(hint.raw_result_matches_target(digest.upper(), digest, 0, False))
        self.assertFalse(hint.raw_result_matches_target("b" * 32, digest, 0, False))
        self.assertTrue(hint.raw_result_matches_target("юзер:" + digest, "u:" + digest, 0, True))

    def test_hashcat_commands_keep_secret_output_in_pipe_and_order_arguments(self):
        exe = Path("/bin/hashcat")
        hashes = Path("/media/USB with spaces/hashes.txt")
        rule = Path("/media/USB with spaces/rules")
        wordlist = Path("/media/USB with spaces/wordlist")
        cmd = hint.make_command(exe, 1000, hashes, "sess", cpu=True, username=True,
                                runtime=30, wordlist=wordlist, rules=rule)
        self.assertEqual(cmd[cmd.index("--attack-mode") + 1], "0")
        self.assertEqual(cmd[cmd.index("--outfile-format") + 1], "1,3")
        self.assertNotIn("--outfile", cmd)
        self.assertIn("--potfile-disable", cmd)
        self.assertIn("--restore-disable", cmd)
        self.assertIn("--logfile-disable", cmd)
        self.assertEqual(cmd[cmd.index("-r") + 1], rule.as_posix())
        self.assertEqual(cmd[cmd.index("--") + 1:], [hashes.as_posix(), wordlist.as_posix()])
        self.assertEqual(cmd[cmd.index("--runtime") + 1], "30")
        self.assertIn("--username", cmd)
        self.assertEqual(cmd[cmd.index("--opencl-device-types") + 1], "1")
        masked = hint.make_command(exe, 0, hashes, "sess", cpu=False, username=False,
                                   runtime=None, mask="?d?d?d?d")
        self.assertEqual(masked[masked.index("--attack-mode") + 1], "3")
        self.assertEqual(masked[masked.index("--") + 1:], [hashes.as_posix(), "?d?d?d?d"])


class StageTests(unittest.TestCase):
    def run_fake(self, output, rc, candidate=b"hint\n"):
        process = ByteProcess(output, rc, stdin=candidate is not None)
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(hint.subprocess, "Popen", return_value=process), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = hint.run_stage(["hashcat"], Path("/"), {}, "session", 0, candidate)
        return result, process, out.getvalue(), err.getvalue()

    def test_valid_match_from_hex_output_and_no_plaintext_saved(self):
        digest = "a" * 32
        output = (digest + ":" + b"p:a".hex() + "\n").encode() + status_line("session", 6, 1)
        result, process, out, _ = self.run_fake(output, 0)
        self.assertEqual(result.outcome, "matched")
        self.assertEqual(result.match, (digest, b"p:a"))
        self.assertEqual(process.stdin.captured, b"hint\n")
        self.assertNotIn("p:a", out)
        self.assertTrue(process.stdout.closed)

    def test_exhausted_requires_final_status_no_rejected_and_consistent_exit(self):
        result, _, _, _ = self.run_fake(status_line("session", 5, 0), 1)
        self.assertEqual(result.outcome, "exhausted")
        for output, rc in ((status_line("session", 5, 0, rejected=1), 1),
                           (status_line("session", 5, 0), 4),
                           (status_line("wrong-session", 5, 0), 1),
                           (status_line("session", 6, 1), 0),
                           (b"", 1)):
            with self.subTest(output=output, rc=rc):
                result, _, _, _ = self.run_fake(output, rc)
                self.assertEqual(result.outcome, "incomplete")

    def test_malformed_match_is_hidden_and_skipped_rule_fails_stage(self):
        digest = "a" * 32
        output = (digest + ":private-not-hex\n").encode() + status_line("session", 5, 0)
        result, _, out, err = self.run_fake(output, 1)
        self.assertEqual(result.outcome, "incomplete")
        self.assertTrue(result.output_warning)
        self.assertNotIn("private-not-hex", out)
        self.assertIn("содержимое скрыто", err)
        output = b"Skipping invalid or unsupported rule in file x\n" + status_line("session", 5, 0)
        result, _, _, _ = self.run_fake(output, 1)
        self.assertEqual(result.outcome, "incomplete")
        self.assertTrue(result.input_warning)

    def test_keyboard_interrupt_stops_child(self):
        class Interrupting:
            def __iter__(self):
                raise KeyboardInterrupt
            def close(self):
                pass

        process = ByteProcess(b"", 130)
        process.stdout = Interrupting()
        with mock.patch.object(hint.subprocess, "Popen", return_value=process):
            result = hint.run_stage(["hashcat"], Path("/"), {}, "session", 0, b"hint\n")
        self.assertEqual(result.outcome, "interrupted")
        self.assertTrue(process.terminated)


class ScenarioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "USB root with spaces"
        self.root.mkdir()
        self.digest = hashlib.md5(b"other:password").hexdigest()
        self.hashes = self.root / "hashes.txt"
        self.hashes.write_text(self.digest + "\n", encoding="utf-8")
        self.base = ["--usb", str(self.root), "--mode", "0", "--hashes", "hashes.txt",
                     "--hint", "seed", "--hashcat", sys.executable]

    def execute(self, stages=(), extra=(), no_mask=True):
        out, err = io.StringIO(), io.StringIO()
        args = self.base + (["--no-mask"] if no_mask else []) + list(extra)
        with mock.patch.object(hint, "filesystem_type", return_value="ext4"), \
                mock.patch.object(hint, "hashcat_version", return_value="v6.2.6"), \
                mock.patch.object(hint, "run_stage", side_effect=list(stages)) as mocked, \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = hint.main(args)
        reports = sorted(self.root.glob("audit-results/*/report.json"))
        return code, out.getvalue(), err.getvalue(), mocked, reports

    @staticmethod
    def report(paths):
        return json.loads(paths[-1].read_text(encoding="utf-8"))

    def test_direct_match_runs_without_hashcat_or_writing_password(self):
        self.hashes.write_text(hashlib.md5(b" with spaces ").hexdigest().upper() + "\n")
        with mock.patch.object(hint, "find_hashcat", side_effect=AssertionError("must not launch")):
            code, out, err, stages, reports = self.execute(extra=("--hint", " with spaces "))
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertIn(": with spaces ", out)
        self.assertEqual(stages.call_count, 0)
        report = self.report(reports)
        self.assertEqual(report["match_stage"], "hint-exact")
        self.assertTrue(report["run_complete"])
        self.assertNotIn(" with spaces ", reports[-1].read_text())
        self.assertFalse((reports[-1].parent / "target-hash.txt").exists())
        self.assertFalse((reports[-1].parent / "cracked.txt").exists())
        self.assertFalse(report["password_file_saved"])

    def test_explicit_save_plaintext_creates_private_file_not_report_secret(self):
        password = " with spaces "
        digest = hashlib.md5(password.encode()).hexdigest()
        self.hashes.write_text(digest + "\n")
        code, out, err, stages, reports = self.execute(extra=("--hint", password, "--save-plaintext"))
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertEqual(stages.call_count, 0)
        result_file = reports[-1].parent / "cracked.txt"
        self.assertEqual(result_file.read_text(), digest + ":" + password + "\n")
        self.assertIn("пароль сохранён", out)
        self.assertTrue(self.report(reports)["password_file_saved"])
        self.assertNotIn(password, reports[-1].read_text())
        if os.name == "posix":
            self.assertEqual(result_file.stat().st_mode & 0o777, 0o600)

    def test_save_failure_is_incomplete_and_warns_about_partial_file(self):
        digest = hashlib.md5(b"secret").hexdigest()
        self.hashes.write_text(digest + "\n")
        with mock.patch.object(hint.os, "fdopen", side_effect=OSError("simulated disk error")):
            code, out, err, stages, reports = self.execute(extra=("--hint", "secret", "--save-plaintext"))
        self.assertEqual(code, 2)
        self.assertIn(digest + ":secret", out)
        self.assertIn("мог быть записан частично", err)
        self.assertEqual(stages.call_count, 0)
        report = self.report(reports)
        self.assertIsNone(report["password_file_saved"])
        self.assertFalse(report["run_complete"])
        self.assertEqual(report["error"], "preparation_or_io_error")
        self.assertNotIn(":secret", reports[-1].read_text())

    def test_explicit_save_binary_candidate_uses_unambiguous_hex(self):
        code, out, _, _, reports = self.execute(
            (stage("matched", self.digest, b"\xff\n"),), extra=("--save-plaintext",),
        )
        self.assertEqual(code, 0)
        self.assertIn(self.digest + ":$HEX[ff0a]", out)
        self.assertEqual((reports[-1].parent / "cracked.txt").read_text(), self.digest + ":$HEX[ff0a]\n")
        self.assertTrue(self.report(reports)["password_file_saved"])

    def test_direct_ntlm_pwdump_outputs_hash_plain_without_username_prefix(self):
        password = "пароль"
        nt = hint.md4_digest(password.encode("utf-16-le")).hex()
        pwdump = "alice:1001:" + "a" * 32 + ":" + nt + ":::"
        self.hashes.write_text(pwdump + "\n")
        code, out, _, stages, reports = self.execute(extra=("--mode", "1000", "--hint", password, "--username"))
        self.assertEqual(code, 0)
        self.assertIn(nt + ":" + password, out)
        self.assertNotIn(pwdump + ":", out)
        self.assertEqual(stages.call_count, 0)
        self.assertTrue(self.report(reports)["run_complete"])

    def test_hint_rules_stop_before_dictionary_or_mask(self):
        code, out, _, stages, reports = self.execute(
            stages=(stage("matched", self.digest, b"other:password"),),
            no_mask=False, extra=("--mask", "?d?d?d?d"),
        )
        self.assertEqual(code, 0)
        self.assertIn(self.digest + ":other:password", out)
        self.assertEqual(stages.call_count, 1)
        command, root, env, session, mode, data = stages.call_args.args
        self.assertEqual(data, b"seed\n")
        self.assertEqual(command[command.index("--attack-mode") + 1], "0")
        self.assertIn("-r", command)
        self.assertIn("--wordlist-autohex-disable", command)
        report = self.report(reports)
        self.assertEqual(report["match_stage"], "hint-rules")
        self.assertEqual([a["stage"] for a in report["attempts"]], ["hint-exact", "hint-rules"])
        self.assertNotIn("other:password", reports[-1].read_text())
        self.assertNotIn("seed", reports[-1].read_text())
        self.assertNotIn("seed", (reports[-1].parent / "hint-rules.rule").read_text())
        self.assertNotIn("seed", (reports[-1].parent / "target-hash.txt").read_text())

    def test_dictionary_after_hint_then_mask_after_dictionary(self):
        self.root.joinpath("wordlist.txt").write_text("some candidate\n")
        results = (stage("exhausted"), stage("exhausted"), stage("matched", self.digest, b"other:password"))
        code, out, _, stages, reports = self.execute(
            results, no_mask=False, extra=("--mask", "?d?d?d?d", "--runtime", "600"),
        )
        self.assertEqual(code, 0)
        self.assertIn(self.digest + ":other:password", out)
        self.assertEqual(stages.call_count, 3)
        commands = [call.args[0] for call in stages.call_args_list]
        self.assertIn("-r", commands[0])
        self.assertEqual(commands[1][-1], (self.root / "wordlist.txt").as_posix())
        self.assertNotIn("--wordlist-autohex-disable", commands[1])
        self.assertEqual(commands[2][-1], "?d?d?d?d")
        self.assertEqual(commands[2][-2], (reports[-1].parent / "target-hash.txt").as_posix())
        for command in commands:
            self.assertEqual(command[command.index("--runtime") + 1], "600")
        report = self.report(reports)
        self.assertEqual([a["stage"] for a in report["attempts"]],
                         ["hint-exact", "hint-rules", "dictionary", "mask-1"])
        self.assertEqual(report["match_stage"], "mask-1")

    def test_multiple_masks_run_in_order_and_stop_after_match(self):
        results = (stage("exhausted"), stage("exhausted"), stage("exhausted"),
                   stage("matched", self.digest, b"other:password"))
        code, out, _, stages, reports = self.execute(
            results, no_mask=False, extra=("--mask", "?d?d", "?d?d?d", "--mask", "?d?d?d?d"),
        )
        self.assertEqual(code, 0)
        self.assertIn(self.digest + ":other:password", out)
        self.assertEqual(stages.call_count, 4)
        self.assertEqual(stages.call_args_list[2].args[0][-1], "?d?d")
        self.assertEqual(stages.call_args_list[3].args[0][-1], "?d?d?d")
        report = self.report(reports)
        self.assertEqual(report["match_stage"], "mask-2")
        self.assertEqual(report["masks_attempted"], 2)
        self.assertFalse(report["mask_skipped"])

    def test_invalid_mask_is_error_not_a_completed_search(self):
        code, out, err, stages, reports = self.execute(
            (stage("exhausted"), stage("exhausted")), no_mask=False, extra=("--mask", "bad\nmask"),
        )
        self.assertEqual(code, 2)
        self.assertIn("Маска", err)
        self.assertNotIn("Пароль не найден", out)
        self.assertEqual(stages.call_count, 2)
        self.assertFalse(self.report(reports)["run_complete"])

    def test_dictionary_uses_public_fallback_and_empty_hint_skips_mutations(self):
        code, out, _, stages, reports = self.execute(
            (stage("exhausted"),), extra=("--hint", "", "--strict"),
        )
        self.assertEqual(code, 1)
        self.assertIn("не найден среди проверенных", out)
        self.assertEqual(stages.call_count, 1)
        self.assertEqual(stages.call_args.args[-1], ("\n".join(usb_audit.COMMON_PASSWORDS) + "\n").encode())
        report = self.report(reports)
        self.assertEqual(report["dictionary_source"], "builtin-weak")
        self.assertEqual([a["stage"] for a in report["attempts"]], ["dictionary"])
        self.assertEqual(report["outcome"], "not_found")
        self.assertTrue(report["run_complete"])
        self.assertTrue(report["mask_skipped"])
        self.assertEqual(report["masks_attempted"], 0)

    def test_salted_exact_uses_hashcat_before_mutation_with_original_target(self):
        target = "$1$salt$4kBwem5qWh8ITot78xC9r0"
        self.hashes.write_text(target + "\n")
        code, out, _, stages, reports = self.execute(
            (stage("matched", target, b"1111"),), extra=("--mode", "500", "--hint", "1111"),
        )
        self.assertEqual(code, 0)
        self.assertIn(target + ":1111", out)
        self.assertEqual(stages.call_count, 1)
        command = stages.call_args.args[0]
        self.assertNotIn("-r", command)
        self.assertEqual((reports[-1].parent / "target-hash.txt").read_text(), target + "\n")
        self.assertEqual(self.report(reports)["match_stage"], "hint-exact")

    def test_incomplete_stage_interrupt_and_wrong_hash_never_run_later_steps(self):
        for result, expected in ((stage("incomplete"), 2), (stage("interrupted"), 130),
                                 (stage("matched", "b" * 32, b"wrong"), 2)):
            with self.subTest(result=result):
                code, out, err, stages, reports = self.execute((result,), no_mask=False, extra=("--mask", "?d?d"))
                self.assertEqual(code, expected)
                self.assertEqual(stages.call_count, 1)
                self.assertNotIn("Пароль не найден", out)
                self.assertNotIn(":wrong", out)
                self.assertFalse(self.report(reports)["run_complete"])
                if expected == 2:
                    self.assertTrue(err)

    def test_explicit_missing_or_external_dictionary_is_error_after_prior_stage(self):
        external = Path(self.temp.name) / "outside.txt"
        external.write_text("candidate\n")
        for path in ("missing.txt", str(external), "hashes.txt"):
            with self.subTest(path=path):
                code, out, err, stages, reports = self.execute(
                    (stage("exhausted"),), extra=("--wordlist", path),
                )
                self.assertEqual(code, 2)
                self.assertTrue(err)
                self.assertEqual(stages.call_count, 1)
                self.assertFalse(self.report(reports)["run_complete"])
                self.assertNotIn("Пароль не найден", out)

    def test_multi_target_and_bad_ntlm_are_rejected_before_hashcat(self):
        self.hashes.write_text(self.digest + "\n" + "b" * 32 + "\n")
        code, _, err, stages, reports = self.execute()
        self.assertEqual(code, 2)
        self.assertIn("ровно одну", err)
        self.assertEqual(stages.call_count, 0)
        self.assertFalse(reports)
        self.hashes.write_text("not-ntlm\n")
        code, _, err, stages, reports = self.execute(extra=("--mode", "1000"))
        self.assertEqual(code, 2)
        self.assertIn("синтаксису", err)
        self.assertEqual(stages.call_count, 0)
        self.assertFalse(reports)

    def test_interactive_prompts_and_main_program_dispatch(self):
        digest = hashlib.md5(b"secret").hexdigest()
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(hint, "filesystem_type", return_value="ext4"), \
                mock.patch("builtins.input", side_effect=["0", digest]) as input_mock, \
                mock.patch.object(hint.getpass, "getpass", return_value="secret") as secret_mock, \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = usb_audit.main(["hint", "--usb", str(self.root), "--no-mask"])
        self.assertEqual(code, 0)
        self.assertEqual(input_mock.call_count, 2)
        secret_mock.assert_called_once()
        self.assertIn(digest + ":secret", out.getvalue())
        self.assertEqual(err.getvalue(), "")

    def test_missing_hint_module_has_actionable_error(self):
        isolated = Path(self.temp.name) / "isolated"
        isolated.mkdir()
        script = isolated / "usb_audit.py"
        script.write_text(Path(usb_audit.__file__).read_text(encoding="utf-8"), encoding="utf-8")
        env = os.environ.copy()
        env["PYTHONPATH"] = ""
        result = subprocess.run([sys.executable, str(script), "hint", "--usb", str(self.root)],
                                cwd=isolated, env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 2)
        self.assertIn("положите crack_with_hint.py рядом", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_malformed_hint_runtime_and_masks_do_not_report_success(self):
        for args in (("--hint", "with\nnewline"), ("--runtime", "0")):
            with self.subTest(args=args):
                if "--runtime" in args:
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as exc:
                        hint.main(self.base + list(args))
                    self.assertEqual(exc.exception.code, 2)
                else:
                    code, _, err, stages, reports = self.execute(extra=args)
                    self.assertEqual(code, 2)
                    self.assertIn("Подсказка", err)
                    self.assertEqual(stages.call_count, 0)
                    self.assertFalse(reports)


if __name__ == "__main__":
    unittest.main()
