"""Offline regressions: no real audio, package, service, router or account actions."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[1]


def load_helper(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "main/scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


codex = load_helper("codex_usage")
updates = load_helper("arch_updates")
fritz = load_helper("fritz_traffic")
systemd = load_helper("systemd_failed_units")


class CodexTests(unittest.TestCase):
    def call_server(self, script, timeout=0.5):
        children = []
        popen = subprocess.Popen

        def start(*args, **kwargs):
            child = popen(*args, **kwargs)
            children.append(child)
            return child

        with patch.object(codex, "CODEX_COMMAND", [sys.executable, "-u", "-c", script]), \
                patch.object(codex, "REQUEST_TIMEOUT_SECONDS", timeout), \
                patch.object(codex.subprocess, "Popen", side_effect=start):
            result = codex.call_rate_limits()
        self.assertIsNotNone(children[0].poll(), "app-server must be reaped")
        self.assertTrue(children[0].stdout.closed)
        return result

    def test_silent_server_has_a_real_deadline(self):
        started = time.monotonic()
        data, error = self.call_server("import time; time.sleep(10)", timeout=0.15)
        self.assertIsNone(data)
        self.assertIn("No account/rateLimits/read response", error)
        self.assertLess(time.monotonic() - started, 1)

    def test_partial_line_cannot_bypass_deadline(self):
        data, error = self.call_server("import sys,time; sys.stdout.write('{'); sys.stdout.flush(); time.sleep(10)", timeout=0.15)
        self.assertIsNone(data)
        self.assertIsNotNone(error)

    def test_fragmented_response_and_handshake(self):
        data, error = self.call_server('''
import json, sys, time
assert json.loads(sys.stdin.readline())["method"] == "initialize"
print(json.dumps({"id": "1", "result": {}}), flush=True)
assert json.loads(sys.stdin.readline())["method"] == "initialized"
assert json.loads(sys.stdin.readline())["method"] == "account/rateLimits/read"
response = json.dumps({"id": "2", "result": {"rateLimits": {"credits": {"balance": "1"}}}}) + "\\n"
sys.stdout.write(response[:12]); sys.stdout.flush()
time.sleep(0.02)
sys.stdout.write(response[12:]); sys.stdout.flush()
time.sleep(10)
''')
        self.assertIsNone(error)
        self.assertEqual(data["credits"]["balance"], "1")

    def test_initialization_error_is_preserved(self):
        data, error = self.call_server('import json; print(json.dumps({"id":"1","error":{"message":"Login rejected"}}), flush=True)')
        self.assertIsNone(data)
        self.assertEqual(error, "Login rejected")

    def test_rate_limit_error_is_preserved(self):
        data, error = self.call_server('''
import json,sys
sys.stdin.readline()
print(json.dumps({"id":"1","result":{}}), flush=True)
sys.stdin.readline(); sys.stdin.readline()
print(json.dumps({"id":"2","error":{"message":"Usage service unavailable"}}), flush=True)
''')
        self.assertIsNone(data)
        self.assertEqual(error, "Usage service unavailable")

    def test_stderr_cannot_block_protocol(self):
        data, error = self.call_server('''
import json,sys
sys.stderr.write("x" * 1000000); sys.stderr.flush()
print(json.dumps({"id":"2","result":{"rateLimits":{"credits":{}}}}), flush=True)
''')
        self.assertIsNone(error)
        self.assertEqual(data, {"credits": {}})


class UpdateTests(unittest.TestCase):
    def check(self, repo, aur, cache=None):
        output = io.StringIO()
        with patch.object(updates, "query_repo_updates", return_value=repo), \
                patch.object(updates, "run_cmd", return_value=aur), \
                patch.object(updates, "repo_for_packages", return_value={"linux": "core"}), \
                patch.object(updates, "load_cache", return_value=cache), \
                patch.object(updates, "save_cache") as save, contextlib.redirect_stdout(output):
            updates.main()
        return json.loads(output.getvalue()), save

    def test_failed_repository_is_not_up_to_date(self):
        result, save = self.check((1, "", "network down"), (0, "", ""))
        self.assertEqual(result["state"], "error")
        self.assertIn("Repository check failed", result["error"])
        save.assert_not_called()

    def test_failed_aur_is_not_up_to_date(self):
        result, save = self.check((0, "", ""), (1, "", "AUR down"))
        self.assertEqual(result["state"], "error")
        self.assertIn("AUR check failed", result["error"])
        save.assert_not_called()

    def test_partial_results_are_explicit(self):
        result, save = self.check((0, "linux 1 -> 2\n", ""), (1, "", "AUR down"))
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["state"], "error")
        save.assert_not_called()

    def test_failure_preserves_last_success_without_overwriting_cache(self):
        cache = updates.payload_for([{"name": "linux", "old": "1", "new": "2", "source": "core"}])
        result, save = self.check((1, "", "timeout"), (0, "", ""), cache)
        self.assertTrue(result["stale"])
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["state"], "error")
        self.assertEqual(cache["status"], "ok")
        self.assertNotIn("error", cache)
        save.assert_not_called()

    def test_checkupdates_exit_two_is_successful_empty_check(self):
        result, save = self.check((2, "", ""), (0, "", ""))
        self.assertEqual(result["state"], "updated")
        self.assertNotIn("error", result)
        save.assert_called_once()

    def test_success_replaces_error_state(self):
        result, save = self.check((0, "linux 1 -> 2\n", ""), (0, "thing 1 -> 2\n", ""))
        self.assertEqual(result["count"], 2)
        self.assertEqual(result["status"], "ok")
        self.assertFalse(result["stale"])
        save.assert_called_once()


class FritzTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = fritz.Config("http://invalid", "", "", 250, 50, .75, .9, .65, 4, False, Path(self.temp.name) / "state.json")

    def assert_invalid(self, xml):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(SystemExit):
            fritz.parse_traffic(xml, self.config)
        result = json.loads(output.getvalue())
        self.assertEqual(result["state"], "error")
        self.assertTrue(result["visible"])
        self.assertTrue(result["error"])

    def test_soap_fault_is_an_error(self):
        self.assert_invalid('<s:Envelope xmlns:s="urn:soap"><s:Fault>Unsupported</s:Fault></s:Envelope>')

    def test_missing_samples_are_an_error(self):
        self.assert_invalid("<Envelope><Newds_current_bps>0</Newds_current_bps></Envelope>")

    def test_invalid_samples_are_an_error(self):
        self.assert_invalid("<Envelope><Newds_current_bps>bad</Newds_current_bps><Newus_current_bps>-1</Newus_current_bps></Envelope>")

    def test_valid_zero_traffic_is_not_an_error(self):
        traffic = fritz.parse_traffic("<Envelope><Newds_current_bps>0,0</Newds_current_bps><Newus_current_bps>0,0</Newus_current_bps></Envelope>", self.config)
        self.assertEqual((traffic.down_mbit, traffic.up_mbit), (0, 0))

    def test_hysteresis_is_preserved(self):
        self.assertTrue(fritz.should_show(self.config, fritz.Traffic(200, 0)))
        self.assertTrue(fritz.should_show(self.config, fritz.Traffic(175, 0)))
        self.assertFalse(fritz.should_show(self.config, fritz.Traffic(100, 0)))


class SystemdTests(unittest.TestCase):
    def test_failed_query_is_unknown_not_empty(self):
        with patch.object(systemd.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "Bus unavailable")):
            units, error = systemd.query_units()
        self.assertIsNone(units)
        self.assertIn("Bus unavailable", error)

    def test_query_timeout_is_reported(self):
        with patch.object(systemd.subprocess, "run", side_effect=subprocess.TimeoutExpired("systemctl", 5)):
            units, error = systemd.query_units()
        self.assertIsNone(units)
        self.assertTrue(error)

    def test_successful_empty_query_is_distinct(self):
        with patch.object(systemd.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")):
            self.assertEqual(systemd.query_units(), ([], ""))

    def test_partial_query_keeps_scope_and_error(self):
        with patch.object(systemd, "query_units", side_effect=[(["failed.service"], ""), (None, "Bus unavailable")]):
            result = systemd.collect()
        self.assertEqual(result["systemUnits"], ["failed.service"])
        self.assertIsNone(result["userUnits"])
        self.assertIn("User services: Bus unavailable", result["error"])

    def restart(self, fail_query=False, fail_restart=False):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            stub = directory / "systemctl"
            stub.write_text('''#!/bin/sh
case " $* " in
  *" --failed "*)
    if [ "$FAIL_QUERY" = 1 ]; then echo 'Bus unavailable' >&2; exit 1; fi
    case " $* " in *" --user "*) exit 0;; esac
    echo 'dummy.service loaded failed failed Dummy'; exit 0;;
esac
if [ "$FAIL_RESTART" = 1 ]; then echo 'Restart denied' >&2; exit 1; fi
exit 0
''')
            stub.chmod(0o700)
            (directory / "qs").write_text("#!/bin/sh\nexit 0\n")
            (directory / "qs").chmod(0o700)
            return subprocess.run(["/usr/bin/bash", str(ROOT / "main/scripts/restart_failed_units.sh")], capture_output=True, text=True, env={**os.environ, "PATH": f"{directory}:/usr/bin", "FAIL_QUERY": str(int(fail_query)), "FAIL_RESTART": str(int(fail_restart))}, timeout=5)

    def test_failed_restart_has_nonzero_status_and_message(self):
        result = self.restart(fail_restart=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Restart denied", result.stderr)

    def test_failed_query_prevents_restart_and_has_error(self):
        result = self.restart(fail_query=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Bus unavailable", result.stderr)

    def test_successful_restart_reports_success(self):
        result = self.restart()
        self.assertEqual(result.returncode, 0)
        self.assertIn("Restarted 1", result.stdout)


class WiringTests(unittest.TestCase):
    def test_bar_passes_ipc_to_all_refreshable_modules(self):
        source = (ROOT / "main/Bar.qml").read_text()
        for name in ("Audio", "Cpu", "Gpu", "Memory", "CodexUsage", "K8sAlerts", "LlamaModels", "Clock"):
            with self.subTest(module=name):
                block = re.search(rf"\b{name}\s*\{{(.*?)\n\s*\}}", source, re.S).group(1)
                self.assertIn("ipc: root.ipc", block)

    @unittest.skipUnless(Path("/usr/bin/qs").exists(), "Quickshell is required for actual-module tests")
    def test_actual_qml_modules_offscreen(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            log = directory / "actions.jsonl"
            # Quickshell's scanner rejects relative imports outside its config.
            # Copy the real modules, rather than modifying the running config.
            shutil.copytree(ROOT / "main", directory / "main", ignore=shutil.ignore_patterns("*.env", "__pycache__"))
            for fixture in (ROOT / "tests/headless").iterdir():
                if fixture.is_file():
                    shutil.copyfile(fixture, directory / fixture.name)
            environment = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "WAYLAND_DISPLAY": "", "DISPLAY": "", "QUICKSHELL_TEST_ACTION_LOG": str(log)}
            process = subprocess.Popen(["qs", "-p", str(directory / "shell.qml"), "--no-color"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=environment)
            ipc = ["qs", "ipc", "-p", str(directory / "shell.qml"), "call", "bar"]
            try:
                deadline = time.monotonic() + 2
                ready = False
                while time.monotonic() < deadline and process.poll() is None:
                    state = subprocess.run([*ipc, "getState"], capture_output=True, text=True, timeout=1, env=environment)
                    if state.returncode == 0:
                        ready = True
                        break
                    time.sleep(0.01)
                self.assertTrue(ready, "isolated IPC handler did not start")
                unknown = subprocess.run([*ipc, "togglePopup", "unknown"], capture_output=True, text=True, timeout=1, env=environment)
                self.assertEqual(unknown.returncode, 0, unknown.stderr)
                self.assertEqual(unknown.stdout.strip(), "false")
                opened = subprocess.run([*ipc, "togglePopup", "calendar"], capture_output=True, text=True, timeout=1, env=environment)
                self.assertEqual(opened.returncode, 0, opened.stderr)
                self.assertEqual(opened.stdout.strip(), "true")
                output, _ = process.communicate(timeout=12)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
            self.assertEqual(process.returncode, 0, output)
            self.assertIn("HEADLESS_FAILURES=0", output)
            self.assertNotIn("FAIL ", output)
            self.assertNotIn("TypeError:", output)
            self.assertNotIn("ReferenceError:", output)
            actions = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(actions, ["first", "second", "fail", "after-failure"])


if __name__ == "__main__":
    unittest.main()
