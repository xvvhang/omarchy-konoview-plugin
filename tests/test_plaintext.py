from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


@unittest.skipUnless(Path('/usr/lib/qt6/bin/qmltestrunner').exists(), 'requires QtTest')
class NoInlineResources(unittest.TestCase):
    def test_production_fallback_does_not_fetch_markup_image(self):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.send_header('Content-Type', 'image/svg+xml')
                self.end_headers()
                self.wfile.write(b'<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>')
            def log_message(self, *_):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix='konoview-text-', dir='/tmp/opencode') as directory:
                directory = Path(directory)
                shutil.copy(Path(__file__).resolve().parents[1] / 'FallbackCaption.qml', directory)
                url = 'http://127.0.0.1:' + str(server.server_port)
                (directory / 'tst_literal.qml').write_text('''import QtQuick
import QtTest
Item {
  width: 400; height: 200
  FallbackCaption { id: production; appClass: '<img src="URL/forbidden">' }
  Text { id: control; textFormat: Text.RichText }
  TestCase {
    name: "NoInlineResources"; when: windowShown
    function test_literal_then_positive_control() {
      compare(production.textFormat, Text.PlainText)
      compare(production.text, '<img src="URL/forbidden">\\nPreview unavailable')
      wait(200)
      control.text = '<img src="URL/positive-control">'
      wait(300)
    }
  }
}
'''.replace('URL', url))
                result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(directory / 'tst_literal.qml')],
                                        env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'},
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('/forbidden', requests)
                self.assertIn('/positive-control', requests, 'HTTP observer must see RichText control')
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
