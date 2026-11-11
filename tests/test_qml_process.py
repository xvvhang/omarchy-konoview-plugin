from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("quickshell"), "requires Quickshell")
class QmlProcessLifecycle(unittest.TestCase):
    def harness(self, body, failed_start=False):
        with tempfile.TemporaryDirectory(prefix="konoview-process-", dir="/tmp/opencode") as directory:
            directory = Path(directory)
            source = (ROOT / "BoundedProcess.qml").read_text()
            if failed_start:
                source = source.replace('"/usr/bin/python3"', '"/nonexistent/konoview-test-python"')
            (directory / "BoundedProcess.qml").write_text(source)
            (directory / "worker.py").write_text('''import json,sys,time
if sys.argv[1] in ("stall", "cancel"): time.sleep(60)
elif sys.argv[1] == "bad": print('{"ok":false}')
else: print(json.dumps({"ok":True,"value":{"args":sys.argv[2:]}}))
''')
            (directory / "shell.qml").write_text("import QtQuick\nimport Quickshell\nShellRoot {\n" + body + "\n}")
            result = subprocess.run(["quickshell", "-n", "-p", str(directory / "shell.qml")],
                                    capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("LIFECYCLE_PASS", output)
            self.assertNotIn("TEST_FAILURE", output)

    def test_args_timeout_cancel_reset_retry(self):
        self.harness('''
  id: root
  property int phase: 0
  function next(mode) { job.operation = mode; Qt.callLater(function() { job.start() }) }
  Component.onCompleted: job.start()
  BoundedProcess {
    id: job; operation: "echo"; arguments: ["sentinel"]
    onSucceeded: function(value) {
      if (value.args.length !== 1 || value.args[0] !== "sentinel") { console.log("TEST_FAILURE args"); Qt.quit(); return }
      if (root.phase === 0) { root.phase = 1; root.next("stall") }
      else if (root.phase === 2) { root.phase = 3; root.next("cancel"); cancelTimer.start() }
      else if (root.phase === 4) { root.phase = 5; root.next("bad") }
      else if (root.phase === 6) { console.log("LIFECYCLE_PASS"); Qt.quit() }
      else { console.log("TEST_FAILURE phase", root.phase); Qt.quit() }
    }
    onFailed: {
      if (root.phase === 1) { root.phase = 2; root.next("echo") }
      else if (root.phase === 5) { root.phase = 6; root.next("echo") }
      else { console.log("TEST_FAILURE failure", root.phase); Qt.quit() }
    }
  }
  Timer { id: cancelTimer; interval: 50; onTriggered: { job.cancel(); retryTimer.start() } }
  Timer { id: retryTimer; interval: 200; onTriggered: {
    if (job.running) { console.log("TEST_FAILURE cancellation"); Qt.quit(); return }
    root.phase = 4; root.next("echo")
  } }
  Timer { running: true; interval: 10000; onTriggered: { console.log("TEST_FAILURE deadline"); Qt.quit() } }
''')

    def test_failed_start_resets_and_allows_retry(self):
        self.harness('''
  id: root
  property int failures: 0
  Component.onCompleted: job.start()
  BoundedProcess {
    id: job; operation: "echo"
    onSucceeded: { console.log("TEST_FAILURE unexpected success"); Qt.quit() }
    onFailed: {
      if (running) { console.log("TEST_FAILURE still running"); Qt.quit(); return }
      root.failures++
      if (root.failures === 2) { console.log("LIFECYCLE_PASS"); Qt.quit() }
      else Qt.callLater(function() { job.start() })
    }
  }
  Timer { running: true; interval: 10000; onTriggered: { console.log("TEST_FAILURE deadline"); Qt.quit() } }
''', failed_start=True)


if __name__ == "__main__":
    unittest.main()
