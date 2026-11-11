import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("worker", Path(__file__).resolve().parents[1] / "worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class BoundedReads(unittest.TestCase):
    def read(self, program, cap=4096, seconds=0.3):
        return worker.bounded_read([sys.executable, "-c", program], cap, seconds)

    def test_normal_exact_cap_and_retry(self):
        self.assertEqual(self.read("import os; os.write(1, b'x'*4096)"), b"x" * 4096)
        with self.assertRaises(worker.ReadFailure):
            self.read("import os; os.write(1,b'x'*4097)")
        self.assertEqual(self.read("print('retry')"), b"retry\n")

    def test_slow_continuous_and_stalled_producers_reaped(self):
        real_popen = subprocess.Popen
        for program in ["import time; time.sleep(60)",
                        "import os,time\nwhile True: os.write(1,b'x'); time.sleep(.01)",
                        "import os,time; os.write(1,b'x'*5000); time.sleep(60)",
                        "import os,time; os.close(1); time.sleep(60)"]:
            started = []
            def track(*args, **kwargs):
                process = real_popen(*args, **kwargs)
                started.append(process)
                return process
            begin = time.monotonic()
            with patch.object(worker.subprocess, "Popen", side_effect=track):
                with self.assertRaises(worker.ReadFailure):
                    self.read(program)
            self.assertLess(time.monotonic() - begin, 1.5)
            self.assertIsNotNone(started[0].returncode)
            with self.assertRaises(ProcessLookupError):
                os.kill(started[0].pid, 0)
            self.assertEqual(self.read("print('retry')"), b"retry\n")

    def test_failed_start_nonzero_invalid_operation(self):
        with self.assertRaises(worker.ReadFailure):
            worker.bounded_read(["/nonexistent/konoview-test"], 10, .1)
        with self.assertRaises(worker.ReadFailure):
            self.read("raise SystemExit(7)")
        with self.assertRaises(worker.ReadFailure):
            worker.run("paste", ["clipboard", "unexpected"])
        self.assertEqual(self.read("print('retry')"), b"retry\n")

    def test_clipboard_primary_caps_and_deadlines(self):
        with patch.object(worker, "bounded_read", return_value=b"hello\nworld") as read:
            self.assertEqual(worker.run("paste", ["clipboard"]), {"text": "hello world"})
            self.assertEqual(read.call_args.args[1:], (4096, 1.0))
            worker.run("paste", ["primary"])
            self.assertIn("--primary", read.call_args.args[0])
        with patch.object(worker, "bounded_read", return_value=b"x" * 4096):
            self.assertEqual(len(worker.run("paste", ["clipboard"])["text"]), 256)

    def test_client_budget_and_markup_literal(self):
        markup = '<img src="https://example.invalid/no-request">'
        clients = [{"mapped": True, "address": hex(i + 1), "pid": i,
                    "title": "x" * 1000, "class": markup + "\x01",
                    "workspace": {"id": 1, "name": "1"}, "size": [1000, 600],
                    "focusHistoryID": 200 - i} for i in range(200)]
        result = worker.clients_reply(json.dumps(clients).encode())
        self.assertEqual(len(result["clients"]), 128)
        self.assertEqual(result["total"], 200)
        self.assertEqual(result["clients"][0]["pid"], 199)
        self.assertEqual(result["clients"][0]["class"], markup + " ")
        self.assertEqual(len(result["clients"][0]["title"]), 512)
        self.assertLess(len(json.dumps(result)), 1024 * 1024)
        for client in clients:
            client['title'] = '\U0001f600' * 512
            client['class'] = '\U0001f600' * 256
            client['workspace']['name'] = '\U0001f600' * 128
        result = worker.clients_reply(json.dumps(clients).encode())
        self.assertLess(len(json.dumps(result)), 2 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
