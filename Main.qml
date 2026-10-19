import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "Layout.js" as Layout

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var settings: ({})
  property bool opened: false
  property real fadeProgress: opened ? 1 : 0
  Behavior on fadeProgress {
    NumberAnimation { duration: root.opened ? 100 : 80; easing.type: Easing.OutCubic }
  }
  onFadeProgressChanged: {
    if (!opened && fadeProgress === 0) {
      prefix = ""
      searchInput.text = ""
      windows = []
    }
  }
  property var windows: []
  property string focusedAddress: ""
  property string prefix: ""
  property string searchText: ""
  readonly property var filteredWindows: {
    var terms = searchText.trim().toLowerCase().split(/\s+/).filter(function(term) { return term.length > 0 })
    return windows.filter(function(w) {
      var haystack = [w.title || "", w.class || "", w.workspace.name || ""].join(" ").toLowerCase()
      return terms.every(function(term) { return haystack.indexOf(term) !== -1 })
    })
  }
  property string errorText: ""
  property double lastTap: 0
  property int tapCount: 0
  property double lastTapInterval: 0
  property string cachedClients: ""
  property real windowRounding: 4
  readonly property string alphabet: "asdfghjklqwertyuiopzxcvbnm"
  property var targetScreen: Quickshell.screens[0] || null

  function tap() {
    var now = Date.now()
    tapCount++
    lastTapInterval = lastTap ? now - lastTap : 0
    if (now - lastTap < 350) { lastTap = 0; toggle() }
    else {
      lastTap = now
      if (!listing.running) listing.running = true
    }
  }
  function toggle() { if (opened) close(); else open() }
  function open() {
    if (opened) return
    prefix = ""
    searchInput.text = ""
    errorText = ""
    windows = []
    focusedAddress = ""
    var toplevels = Hyprland.toplevels.values
    for (var t = 0; t < toplevels.length; t++)
      if (toplevels[t].activated) focusedAddress = toplevels[t].address
    var monitor = Hyprland.focusedMonitor
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (monitor && Quickshell.screens[i].name === monitor.name)
        targetScreen = Quickshell.screens[i]
    Hyprland.refreshToplevels()
    if (!roundingQuery.running) roundingQuery.running = true
    opened = true
    if (cachedClients) populate(cachedClients)
    if (!listing.running) listing.running = true
    Qt.callLater(function() { keyboard.forceActiveFocus() })
  }
  function close() {
    opened = false
  }
  function hint(index, count) {
    var length = Math.max(1, Math.ceil(Math.log(Math.max(2, count)) / Math.log(alphabet.length)))
    var text = ""
    for (var i = 0; i < length; i++) {
      text = alphabet[index % alphabet.length] + text
      index = Math.floor(index / alphabet.length)
    }
    return text
  }
  function populate(text) {
    cachedClients = text
    if (!opened) return
    try {
      var clients = JSON.parse(text).filter(function(w) { return w.mapped })
      // An exclusive layer clears toplevel activation; Hyprland retains the
      // most recently focused client in its focus history while it is open.
      for (var f = 0; f < clients.length; f++)
        if (clients[f].focusHistoryID === 0) focusedAddress = clients[f].address
      clients.sort(function(a, b) {
        var aw = a.workspace.id < 0 ? 100000 - a.workspace.id : a.workspace.id
        var bw = b.workspace.id < 0 ? 100000 - b.workspace.id : b.workspace.id
        return aw - bw || a.address.localeCompare(b.address)
      })
      for (var i = 0; i < clients.length; i++) {
        var w = clients[i]
        w.hint = hint(i, clients.length)
      }
      windows = clients
    } catch (e) { errorText = "Could not read Hyprland windows" }
  }
  function handleFor(address) {
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++)
      if (list[i].address.replace(/^0x/, "") === address.replace(/^0x/, ""))
        return list[i].wayland
    return null
  }
  function select(w) {
    if (!w) return
    var address = w.address
    close()
    // Defer until the exclusive layer has released keyboard focus.
    focusLater.address = address
    focusLater.restart()
  }
  Timer {
    id: focusLater
    property string address: ""
    interval: 30
    onTriggered: Hyprland.dispatch("hl.dsp.focus({window=" + JSON.stringify("address:" + address) + "})")
  }
  function typeHint(text) {
    var next = prefix + text.toLowerCase()
    var matches = filteredWindows.filter(function(w) { return w.hint.indexOf(next) === 0 })
    if (!matches.length) { prefix = ""; return }
    prefix = next
    if (matches.length === 1 && matches[0].hint === next) select(matches[0])
  }
  IpcHandler {
    target: "xvvhang.overview"
    function tap(): void { root.tap() }
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function choose(hint: string): void { if (root.opened) root.typeHint(hint) }
    function status(): string { return JSON.stringify({opened: root.opened, windows: root.windows.length, matchingWindows: root.filteredWindows.length, searchFocused: searchInput.activeFocus, focusedAddress: root.focusedAddress, rounding: root.windowRounding, tapCount: root.tapCount, lastTapInterval: root.lastTapInterval}) }
  }
  Component.onCompleted: {
    listing.running = true
    roundingQuery.running = true
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded" && !roundingQuery.running) roundingQuery.running = true
    }
  }
  // Also pick up runtime keyword changes while the overview is visible.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: if (!roundingQuery.running) roundingQuery.running = true
  }
  Process {
    id: roundingQuery
    command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var value = JSON.parse(text).int
          if (typeof value === "number") root.windowRounding = Math.max(0, value)
        } catch (e) { console.warn("overview", "Could not read window rounding") }
      }
    }
  }
  Process {
    id: listing
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { onStreamFinished: root.populate(text) }
    onExited: function(code) { if (code !== 0) root.errorText = "hyprctl clients failed" }
  }

  PanelWindow {
    id: overlay
    visible: root.opened || root.fadeProgress > 0
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    // Same theme-aware scrim as the Super+K menu; no background capture or blur.
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "alec-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onVisibleChanged: if (visible) Qt.callLater(function() { keyboard.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.fadeProgress
    }

    Item {
      id: keyboard
      anchors.fill: parent
      opacity: root.fadeProgress
      enabled: root.opened
      focus: true
      Keys.onPressed: function(event) {
        if (searchInput.activeFocus) return
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (event.key === Qt.Key_Escape) root.close()
        else if (event.key === Qt.Key_Backspace) root.prefix = root.prefix.slice(0, -1)
        else if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.prefix = ""; searchInput.forceActiveFocus() }
        else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) root.typeHint(String.fromCharCode(event.key))
        event.accepted = true
      }
      Rectangle {
        id: header
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 36 }
        width: Math.min(320, parent.width - 72)
        height: 36
        radius: root.windowRounding
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.8)
        border.width: 1
        border.color: searchInput.activeFocus ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.22)
        TextInput {
          id: searchInput
          anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
          verticalAlignment: TextInput.AlignVCenter
          color: Color.foreground
          selectionColor: Color.accent
          selectedTextColor: Color.background
          font.family: Style.font.family
          font.pixelSize: 13
          clip: true
          selectByMouse: true
          onTextChanged: {
            root.searchText = text
            root.prefix = ""
            if (windowScroll.contentItem) windowScroll.contentItem.contentY = 0
          }
          Keys.onEscapePressed: function(event) {
            keyboard.forceActiveFocus()
            event.accepted = true
          }
          Keys.onReturnPressed: function(event) {
            keyboard.forceActiveFocus()
            event.accepted = true
          }
          Keys.onEnterPressed: function(event) {
            keyboard.forceActiveFocus()
            event.accepted = true
          }
        }
        Text {
          anchors.centerIn: parent
          visible: searchInput.text.length === 0 && searchInput.preeditText.length === 0
          text: searchInput.activeFocus ? "Search windows…" : "Press Enter to search"
          color: Color.foreground
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: 13
        }
      }
      ScrollView {
        id: windowScroll
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 36; topMargin: 32 }
        clip: true
        contentWidth: availableWidth
        Column {
          id: windowGrid
          width: windowScroll.availableWidth
          spacing: 24
          readonly property var rows: Layout.rows(root.filteredWindows)
          Repeater {
            model: windowGrid.rows
            delegate: Item {
              id: windowRow
              required property var modelData
              width: windowGrid.width
              height: rowContent.implicitHeight
              readonly property real previewScale: {
                var totalWidth = 0, maxHeight = 1
                for (var i = 0; i < modelData.length; i++) {
                  var size = modelData[i].size || [640, 400]
                  totalWidth += Math.max(1, size[0])
                  maxHeight = Math.max(maxHeight, size[1])
                }
                var widthScale = Math.max(1, width - 24 * (modelData.length - 1)) / Math.max(1, totalWidth)
                var rowBudget = Math.max(160, (windowScroll.height - 24 * (windowGrid.rows.length - 1)) / Math.max(1, windowGrid.rows.length) - 30)
                return Math.min(widthScale, rowBudget / maxHeight)
              }
              Row {
                id: rowContent
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24
                Repeater {
                  model: windowRow.modelData
            delegate: Column {
              id: tile
              required property var modelData
              readonly property bool wasFocused: modelData.address.replace(/^0x/, "") === root.focusedAddress.replace(/^0x/, "")
              width: Math.max(1, (modelData.size || [640, 400])[0] * windowRow.previewScale)
              spacing: 8
              opacity: !root.prefix || modelData.hint.indexOf(root.prefix) === 0 ? 1 : 0.25
              ClippingRectangle {
                id: card
                readonly property var handle: root.handleFor(tile.modelData.address)
                width: parent.width
                height: Math.max(1, (tile.modelData.size || [640, 400])[1] * windowRow.previewScale)
                radius: root.windowRounding
                color: "transparent"
                contentInsideBorder: false
                border.width: tile.wasFocused || hover.containsMouse ? 2 : 1
                border.color: tile.wasFocused ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, hover.containsMouse ? 0.65 : 0.3)
                Item {
                  anchors.fill: parent
                  clip: true
                  ScreencopyView {
                    id: preview
                    anchors.fill: parent
                    captureSource: card.handle
                    live: root.opened
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: !preview.hasContent
                    text: (tile.modelData.class || "Window") + "\nPreview unavailable"
                    horizontalAlignment: Text.AlignHCenter
                    color: Color.foreground; opacity: 0.5; font.family: Style.font.family
                  }
                }
                MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.select(tile.modelData) }
              }
              Item {
                width: parent.width
                height: Math.max(22, hintText.implicitHeight + 4)
                Text {
                  anchors { left: parent.left; right: metadata.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                  textFormat: Text.PlainText
                  text: tile.modelData.title || tile.modelData.class || "Untitled window"
                  elide: Text.ElideRight
                  color: Color.foreground; font.family: Style.font.family; font.pixelSize: 13
                }
                Rectangle {
                  id: metadata
                  anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                  width: Math.min(hintText.implicitWidth + 12, tile.width * 0.65)
                  height: hintText.implicitHeight + 4
                  radius: root.windowRounding
                  color: Color.accent
                  Text {
                    id: hintText
                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: (tile.modelData.workspace.name === "special:scratchpad" ? "S" : tile.modelData.workspace.name.replace(/^special:/, "")) + ":" + tile.modelData.hint.toUpperCase()
                    elide: Text.ElideRight
                    color: Color.background
                    font.family: Style.font.family
                    font.bold: true
                    font.pixelSize: 13
                  }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.select(tile.modelData) }
              }
            }
          }
                }
              }
            }
          Text {
            visible: root.filteredWindows.length === 0
            text: root.errorText || (listing.running ? "Loading windows…" : root.searchText.trim() ? "No matching windows" : "No windows")
            color: Color.foreground; font.family: Style.font.family
          }
        }
      }
    }
  }
}
