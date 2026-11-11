import QtQuick
import QtQuick.Controls

TextInput {
  id: input
  property bool panelActive: false
  property int revision: 0
  property int panelRevision: 0
  property int requestRevision: -1
  property int requestStart: 0
  property int requestEnd: 0
  property string pasteError: ""
  // Tests can disable the external reader without accessing real clipboards.
  property bool clipboardReadsEnabled: true
  readonly property var pasteRead: pasteLoader.item
  maximumLength: 256
  selectByMouse: true

  function invalidatePaste() {
    revision++
    if (pasteRead) pasteRead.cancel()
  }
  // Connections cannot be overridden by consumers' onTextChanged handlers.
  Connections {
    target: input
    function onPanelActiveChanged() { input.panelRevision++; input.invalidatePaste(); pasteMenu.close() }
    function onActiveFocusChanged() { input.invalidatePaste() }
    function onTextChanged() { input.invalidatePaste() }
    function onCursorPositionChanged() { input.invalidatePaste() }
    function onSelectionStartChanged() { input.invalidatePaste() }
    function onSelectionEndChanged() { input.invalidatePaste() }
    function onPreeditTextChanged() { input.invalidatePaste() }
  }

  function requestPaste(primary) {
    if (!panelActive || !activeFocus || !pasteRead || pasteRead.running) return
    revision++
    pasteError = ""
    requestRevision = revision
    requestStart = selectionStart
    requestEnd = selectionEnd
    pasteRead.arguments = [primary ? "primary" : "clipboard"]
    pasteRead.start()
  }
  function acceptPaste(value) {
    if (!panelActive || !activeFocus || revision !== requestRevision || preeditText.length) return
    var valueText = typeof value.text === "string" ? value.text : ""
    var available = maximumLength - text.length + requestEnd - requestStart
    var replacement = valueText.slice(0, Math.max(0, available))
    // Snapshot positions before remove() emits edit/cursor/selection signals.
    var begin = requestStart, end = requestEnd
    remove(begin, end)
    insert(begin, replacement)
    cursorPosition = begin + replacement.length
  }
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    // Consume before Qt's native paste/read, including platform standard keys.
    if (event.matches(StandardKey.Paste) || event.key === Qt.Key_Paste
        || (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier))
        || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
      event.accepted = true
      if (!event.isAutoRepeat) requestPaste(false)
    }
  }
  // TextInput has no built-in menu. Own right/middle pointer gestures so no
  // native primary-selection read or implicit clipboard availability query runs.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    preventStealing: true
    onPressed: function(mouse) {
      mouse.accepted = true
      if (!input.panelActive) return
      if (mouse.button === Qt.MiddleButton) {
        input.forceActiveFocus()
        input.cursorPosition = input.positionAt(mouse.x, mouse.y)
        input.requestPaste(true)
      } else {
        input.forceActiveFocus()
        pasteMenu.popup()
      }
    }
    onReleased: function(mouse) { mouse.accepted = true }
    onDoubleClicked: function(mouse) { mouse.accepted = true }
    onPressAndHold: function(mouse) { mouse.accepted = true }
  }
  Menu {
    id: pasteMenu
    MenuItem {
      text: "Paste"
      onTriggered: {
        var lifetime = input.panelRevision
        var value = input.text, cursor = input.cursorPosition
        var begin = input.selectionStart, end = input.selectionEnd
        Qt.callLater(function() {
          if (input.panelActive && input.panelRevision === lifetime && input.text === value
              && input.cursorPosition === cursor && input.selectionStart === begin && input.selectionEnd === end) {
            input.forceActiveFocus()
            input.requestPaste(false)
          }
        })
      }
    }
  }
  Loader {
    id: pasteLoader
    active: input.clipboardReadsEnabled
    source: "BoundedProcess.qml"
    onLoaded: item.operation = "paste"
  }
  Connections {
    target: input.pasteRead
    function onSucceeded(value) { input.acceptPaste(value) }
    function onFailed(message) {
      if (input.panelActive && input.activeFocus && input.revision === input.requestRevision)
        input.pasteError = "Paste failed; try again"
    }
  }
}
