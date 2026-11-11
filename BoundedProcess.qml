import QtQuick
import Quickshell.Io

Item {
  id: root
  property string operation: ""
  property var arguments: []
  property bool running: false
  property bool cancelled: false
  property string output: ""
  signal succeeded(var value)
  signal failed(string message)

  function start() {
    if (running || worker.running) return false
    output = ""
    cancelled = false
    running = true
    worker.command = ["/usr/bin/python3", "-B", decodeURIComponent(Qt.resolvedUrl("worker.py").toString().replace(/^(file|qs):\/\//, "")), root.operation].concat(root.arguments)
    watchdog.restart()
    worker.running = true
    return true
  }
  function cancel() {
    if (!running || cancelled) return
    cancelled = true
    worker.signal(15)
    killLater.restart()
  }
  function finish(code) {
    if (!running) return
    watchdog.stop()
    killLater.stop()
    running = false
    var raw = output
    output = ""
    if (cancelled) return
    if (code === 0) {
      try {
        const reply = JSON.parse(raw)
        if (reply.ok === true) { succeeded(reply.value); return }
      } catch (e) {}
    }
    failed("Read failed; try again")
  }
  Process {
    id: worker
    // The producer is bounded outside the GUI; only normalized helper output
    // reaches this collector (under 2 MiB, including worst-case JSON escapes).
    stdout: StdioCollector { onStreamFinished: root.output = text }
    onExited: function(code, status) { root.finish(status === 0 ? code : -1) }
  }
  Timer {
    id: watchdog
    interval: 3000
    // Covers interpreter/helper failed-start as well as a stuck helper.
    onTriggered: {
      worker.signal(15)
      killLater.restart()
    }
  }
  Timer {
    id: killLater
    interval: 100
    onTriggered: {
      worker.signal(9)
      root.finish(-1)
    }
  }
  Component.onDestruction: worker.signal(15)
}
