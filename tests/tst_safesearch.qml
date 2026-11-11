import QtQuick
import QtTest
import ".."

Item {
  width: 400
  height: 200
  SafeSearch {
    id: search
    width: 300
    height: 40
    panelActive: true
    clipboardReadsEnabled: false
    property int requests: 0
    property bool primary: false
    // Do not touch the user's clipboard. Test event interception here, and
    // producer limits/deadlines with isolated subprocesses in test_worker.py.
    function requestPaste(usePrimary) { requests++; primary = usePrimary }
  }
  Item { id: other; y: 80; width: 100; height: 40; focus: false }
  FallbackCaption { id: fallback; y: 130 }
  TestCase {
    name: "SafeSearch"
    when: windowShown
    function init() {
      search.panelActive = true
      search.text = "abc"
      search.cursorPosition = 1
      search.requests = 0
      search.forceActiveFocus()
      tryCompare(search, "activeFocus", true)
    }
    function cleanup() { search.panelActive = false }
    function test_keyboard_routes() {
      keyClick(Qt.Key_V, Qt.ControlModifier)
      keyClick(Qt.Key_Insert, Qt.ShiftModifier)
      keyClick(Qt.Key_Paste)
      compare(search.requests, 3)
      compare(search.text, "abc")
    }
    function test_middle_selection() {
      mouseClick(search, 10, 10, Qt.MiddleButton)
      compare(search.requests, 1)
      compare(search.primary, true)
      compare(search.text, "abc")
    }
    function test_context_menu_route() {
      mouseClick(search, 10, 10, Qt.RightButton)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      tryCompare(search, "requests", 1)
      compare(search.primary, false)
      compare(search.text, "abc")
    }
    function test_fallback_plaintext() {
      var markup = '<img src="http://127.0.0.1:9/must-not-load">'
      fallback.appClass = markup
      compare(fallback.textFormat, Text.PlainText)
      compare(fallback.text, markup + "\nPreview unavailable")
      fallback.appClass = "x".repeat(1000) + "\u202e"
      compare(fallback.text, "x".repeat(256) + "\nPreview unavailable")
    }
    function prepare() {
      search.select(1, 2)
      search.requestStart = 1
      search.requestEnd = 2
      search.requestRevision = search.revision
    }
    function test_selection_replace() {
      prepare()
      search.acceptPaste({text: "XYZ"})
      compare(search.text, "aXYZc")
    }
    function test_stale_edit_selection_focus_lifetime() {
      prepare(); search.text = "edited"; search.acceptPaste({text: "BAD"}); compare(search.text, "edited")
      search.text = "abc"; prepare(); search.cursorPosition = 0; search.acceptPaste({text: "BAD"}); compare(search.text, "abc")
      prepare(); other.forceActiveFocus(); search.forceActiveFocus(); search.acceptPaste({text: "BAD"}); compare(search.text, "abc")
      prepare(); search.panelActive = false; search.panelActive = true; search.acceptPaste({text: "BAD"}); compare(search.text, "abc")
    }
    function test_maximum_length() {
      search.text = "x".repeat(255)
      search.cursorPosition = 255
      search.requestStart = 255
      search.requestEnd = 255
      search.requestRevision = search.revision
      search.acceptPaste({text: "abcdef"})
      compare(search.text.length, 256)
    }
  }
}
