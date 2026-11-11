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
    // Match Omarchy Menu's instant entrance; keep the short exit fade.
    NumberAnimation { duration: Style.duration(root.opened ? 0 : 80); easing.type: Easing.OutCubic }
  }
  onFadeProgressChanged: {
    if (!opened && fadeProgress === 0) {
      prefix = ""
      searchInput.text = ""
      windows = []
      selectedAddress = ""
    }
  }
  property var windows: []
  property string focusedAddress: ""
  property string selectedAddress: ""
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
  property int pressCount: 0
  property double lastTapInterval: 0
  property bool suppressNextTap: false
  property string cachedClients: ""
  property int totalWindows: 0
  // Metadata and scene-graph budgets are independent of the client population.
  readonly property int maxWindows: 128
  readonly property int maxCaptures: 12
  readonly property var captureAddresses: {
    var scale = 2
    var monitors = Hyprland.monitors.values
    for (var m = 0; m < monitors.length; m++)
      if (targetScreen && monitors[m].name === targetScreen.name && isFinite(monitors[m].scale)) scale = Math.max(1, monitors[m].scale)
    var candidates = filteredWindows.slice()
    candidates.sort(function(a, b) { return Number(b.address === priorityAddress) - Number(a.address === priorityAddress) })
    var result = [], pixels = 0
    for (var i = 0; i < candidates.length && result.length < maxCaptures; i++) {
      var w = candidates[i]
      var cost = w.size[0] * w.size[1] * scale * scale
      if (cost > 16 * 1024 * 1024 || pixels + cost > 48 * 1024 * 1024) continue
      result.push(w.address)
      pixels += cost
    }
    return result
  }
  property double openStartedAt: 0
  property int openSyncMs: 0
  property int populateMs: 0
  property int firstPreviewMs: -1
  property int cachedPreviewMs: -1
  property int layerVisibleMs: -1
  property int previewCreations: 0
  property int firstCaptureSourceMs: -1
  property int firstCaptureWaitMs: -1
  property bool remainingCapturesEnabled: false
  readonly property string priorityAddress: {
    for (var i = 0; i < filteredWindows.length; i++)
      if (filteredWindows[i].address === focusedAddress) return focusedAddress
    return filteredWindows.length ? filteredWindows[0].address : ""
  }
  property var cachedPreviews: ({})
  property int snapshotGeneration: 0
  signal snapshotRequested()
  property real windowRounding: 4
  readonly property string alphabet: "adfghjklqwertyuiopzxcvbnm"
  property var targetScreen: Quickshell.screens[0] || null

  function press() {
    pressCount++
    // A new press also recovers if the previous release was not delivered.
    suppressNextTap = false
    var now = Date.now()
    if (lastTap && now - lastTap < 350) {
      lastTapInterval = now - lastTap
      lastTap = 0
      suppressNextTap = true
      toggle()
    }
  }
  function tap() {
    if (suppressNextTap) { suppressNextTap = false; return }
    var now = Date.now()
    tapCount++
    lastTapInterval = lastTap ? now - lastTap : 0
    if (now - lastTap < 350) { lastTap = 0; toggle() }
    else {
      lastTap = now
      listing.start()
    }
  }
  function toggle() { if (opened) close(); else open() }
  function open() {
    if (opened) return
    openStartedAt = Date.now()
    firstPreviewMs = -1
    cachedPreviewMs = -1
    layerVisibleMs = -1
    previewCreations = 0
    firstCaptureSourceMs = -1
    firstCaptureWaitMs = -1
    snapshotGeneration++
    remainingCapturesEnabled = false
    focusLater.stop()
    selectedAddress = ""
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
    roundingQuery.start()
    opened = true
    if (cachedClients) populate(cachedClients)
    listing.start()
    remainingCaptureFallback.restart()
    Qt.callLater(function() { keyboard.forceActiveFocus() })
    openSyncMs = Date.now() - openStartedAt
  }
  function close() {
    selectionLater.stop()
    listing.cancel()
    roundingQuery.cancel()
    remainingCaptureFallback.stop()
    startRemainingCaptures.stop()
    if (opened) snapshotRequested()
    opened = false
  }
  Timer {
    id: remainingCaptureFallback
    interval: 250
    onTriggered: if (root.opened) root.remainingCapturesEnabled = true
  }
  Timer {
    id: startRemainingCaptures
    interval: 16
    onTriggered: {
      remainingCaptureFallback.stop()
      if (root.opened) root.remainingCapturesEnabled = true
    }
  }
  function cacheKey(w) { return w.address + ":" + w.pid }
  function storeSnapshot(key, result, generation) {
    if (generation !== snapshotGeneration || !result || !result.url) return
    var next = Object.assign({}, cachedPreviews)
    delete next[key]
    // Bound retained thumbnail memory, even with unusually many windows.
    var keys = Object.keys(next)
    if (keys.length >= 64) delete next[keys[0]]
    next[key] = result
    cachedPreviews = next
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
    if (text.length > 2 * 1024 * 1024) { errorText = "Window reply too large"; return }
    cachedClients = text
    if (!opened) return
    var startedAt = Date.now()
    try {
      var reply = JSON.parse(text)
      if (!Array.isArray(reply.clients) || reply.clients.length > maxWindows) throw new Error("Window budget exceeded")
      var clients = reply.clients
      totalWindows = reply.total
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
      // A fresh query often repeats the cached list used by open(). Replacing
      // an unchanged array rebuilds every preview and restarts screencopy.
      var unchanged = clients.length === windows.length
      for (var c = 0; unchanged && c < clients.length; c++) {
        var a = clients[c], b = windows[c]
        unchanged = a.address === b.address && a.title === b.title && a.class === b.class
          && a.hint === b.hint && a.workspace.id === b.workspace.id && a.workspace.name === b.workspace.name
          && a.pid === b.pid && JSON.stringify(a.size) === JSON.stringify(b.size)
      }
      if (!unchanged) windows = clients
      var retained = {}
      for (var p = 0; p < clients.length; p++) {
        var key = cacheKey(clients[p])
        if (cachedPreviews[key]) retained[key] = cachedPreviews[key]
      }
      cachedPreviews = retained
      populateMs = Date.now() - startedAt
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
    if (!w || !opened || selectionLater.running) return
    selectedAddress = w.address
    selectionLater.command = "hl.dsp.focus({window=" + JSON.stringify("address:" + w.address) + "})"
    selectionLater.restart()
  }
  function selectWorkspace(key) {
    if (!opened || selectionLater.running) return
    var workspace = key.toLowerCase() === "s" ? "special:scratchpad" : key === "0" ? "10" : key
    for (var i = 0; i < filteredWindows.length; i++) {
      var w = filteredWindows[i]
      if (workspace === "special:scratchpad" ? w.workspace.name === workspace : String(w.workspace.id) === workspace) {
        select(w)
        return
      }
    }
    dispatchAfterClose("hl.dsp.focus({workspace=" + JSON.stringify(workspace) + "})")
  }
  Timer {
    id: selectionLater
    property string command: ""
    interval: 120
    onTriggered: root.dispatchAfterClose(command)
  }
  function dispatchAfterClose(command) {
    close()
    // Defer until the exclusive layer has released keyboard focus.
    focusLater.command = command
    focusLater.restart()
  }
  Timer {
    id: focusLater
    property string command: ""
    interval: 30
    onTriggered: Hyprland.dispatch(command)
  }
  function typeHint(text) {
    var next = prefix + text.toLowerCase()
    var matches = filteredWindows.filter(function(w) { return w.hint.indexOf(next) === 0 })
    if (!matches.length) { prefix = ""; return }
    prefix = next
    if (matches.length === 1 && matches[0].hint === next) select(matches[0])
  }
  ShellIpc {
    target: "konochi.konoview"
    function captureTiming(): string { return JSON.stringify({previewCreations: root.previewCreations, firstCaptureSourceMs: root.firstCaptureSourceMs, firstCaptureWaitMs: root.firstCaptureWaitMs, firstPreviewMs: root.firstPreviewMs}) }
    function press(): void { root.press() }
    function tap(): void { root.tap() }
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function choose(hint: string): void { if (root.opened) root.typeHint(hint) }
    function status(): string { return JSON.stringify({opened: root.opened, windows: root.windows.length, matchingWindows: root.filteredWindows.length, searchFocused: searchInput.activeFocus, focusedAddress: root.focusedAddress, rounding: root.windowRounding, pressCount: root.pressCount, tapCount: root.tapCount, lastTapInterval: root.lastTapInterval, startup: {openSyncMs: root.openSyncMs, populateMs: root.populateMs, firstPreviewMs: root.firstPreviewMs, cachedPreviewMs: root.cachedPreviewMs, layerVisibleMs: root.layerVisibleMs, cachedPreviews: Object.keys(root.cachedPreviews).length}}) }
  }
  Component.onCompleted: {
    installLayerRule()
    listing.start()
    roundingQuery.start()
  }
  // An owner token prevents an old instance's deferred cleanup from disabling
  // the replacement instance's rule during shell/plugin hot reloads.
  readonly property string layerRuleOwner: Date.now().toString() + "-" + Math.random().toString(36).slice(2)
  function installLayerRule() {
    if (layerRuleInstall.running) layerRuleInstall.pending = true
    else layerRuleInstall.start()
  }
  Component.onDestruction: Quickshell.execDetached([
    "/usr/bin/python3", "-B", decodeURIComponent(Qt.resolvedUrl("worker.py").toString().replace(/^(file|qs):\/\//, "")), "rule",
    "if konochi_konoview_blur and konochi_konoview_blur.owner == " + JSON.stringify(layerRuleOwner) +
    " then konochi_konoview_blur.rule:set_enabled(false); konochi_konoview_blur = nil end"
  ])
  BoundedProcess {
    id: layerRuleInstall
    property bool pending: false
    operation: "rule"
    arguments: [
      "konochi_konoview_blur = { owner = " + JSON.stringify(root.layerRuleOwner) +
      ", rule = hl.layer_rule({ name = \"konochi-konoview-blur\", match = { namespace = \"^konochi-konoview$\" }, blur = true, no_anim = true, animation = \"none\" }) }"]
    function finishInstall() {
      if (pending) {
        pending = false
        Qt.callLater(function() { layerRuleInstall.start() })
      }
    }
    onSucceeded: finishInstall()
    onFailed: function(message) { console.warn("konoview", "Could not register layer rule:", message); finishInstall() }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") {
        root.installLayerRule()
        roundingQuery.start()
      }
    }
  }
  // Also pick up runtime keyword changes while the overview is visible.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: roundingQuery.start()
  }
  BoundedProcess {
    id: roundingQuery
    operation: "rounding"
    onSucceeded: function(value) { root.windowRounding = value.rounding }
    onFailed: function(message) { console.warn("konoview", "Could not read window rounding:", message) }
  }
  BoundedProcess {
    id: listing
    operation: "clients"
    onSucceeded: function(value) { root.errorText = ""; root.populate(JSON.stringify(value)) }
    onFailed: function(message) { root.errorText = "Could not read windows; reopen to retry" }
  }

  PanelWindow {
    id: overlay
    visible: root.opened || root.fadeProgress > 0
    onBackingWindowVisibleChanged: {
      if (backingWindowVisible && root.opened)
        root.layerVisibleMs = Date.now() - root.openStartedAt
    }
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    // Same theme-aware scrim as Super+K, with compositor blur managed above.
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "konochi-konoview"
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
        if (selectionLater.running && event.key !== Qt.Key_Escape) { event.accepted = true; return }
        if (searchInput.activeFocus) return
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (event.key === Qt.Key_Escape) root.close()
        else if (event.key === Qt.Key_Backspace) root.prefix = root.prefix.slice(0, -1)
        else if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.prefix = ""; searchInput.forceActiveFocus() }
        else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) root.selectWorkspace(String.fromCharCode(event.key))
        else if (event.key === Qt.Key_S) root.selectWorkspace("s")
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
        SafeSearch {
          id: searchInput
          panelActive: root.opened
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
          textFormat: Text.PlainText
          visible: searchInput.text.length === 0 && searchInput.preeditText.length === 0
          text: searchInput.activeFocus ? "Search windows…" : "Press Enter to search"
          color: Color.foreground
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: 13
        }
        Text {
          anchors { top: parent.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
          textFormat: Text.PlainText
          text: searchInput.pasteError || root.errorText || (root.totalWindows > root.maxWindows ? "Showing the 128 most recent windows" : "")
          color: Color.foreground
          font.pixelSize: 11
        }
      }
      ScrollView {
        id: windowScroll
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 36; topMargin: 32 }
        clip: true
        contentWidth: availableWidth
        Column {
          id: windowGrid
          // A newly mapped PanelWindow initially reports 0x0. Use the selected
          // screen's geometry until configure arrives, avoiding a bogus one-column
          // layout that would immediately destroy and recreate every capture.
          width: windowScroll.availableWidth > 0 ? windowScroll.availableWidth : Math.max(1, (root.targetScreen ? root.targetScreen.width : 1440) - 72)
          spacing: 24
          readonly property real layoutHeight: windowScroll.height > 0 ? windowScroll.height : Math.max(1, (root.targetScreen ? root.targetScreen.height : 900) - 140)
          readonly property var arrangement: Layout.arrange(root.filteredWindows, width, layoutHeight)
          // Geometry changes should resize existing captures, not replace their
          // array models. Rebuild rows only when membership/capacity changes.
          readonly property int columns: arrangement.columns
          readonly property var rows: columns > 0 ? Layout.rows(root.filteredWindows, columns) : []
          readonly property real previewScale: arrangement.scale
          readonly property real previewLeft: arrangement.left
          Repeater {
            model: windowGrid.rows
            delegate: Item {
              id: windowRow
              required property var modelData
              width: windowGrid.width
              height: rowContent.implicitHeight
              Row {
                id: rowContent
                x: windowGrid.previewLeft
                spacing: 24
                Repeater {
                  model: windowRow.modelData
            delegate: Column {
              id: tile
              required property var modelData
              readonly property bool wasFocused: modelData.address.replace(/^0x/, "") === root.focusedAddress.replace(/^0x/, "")
              readonly property bool selected: modelData.address === root.selectedAddress
              width: Math.max(1, (modelData.size || [640, 400])[0] * windowGrid.previewScale)
              spacing: 8
              opacity: root.selectedAddress ? (selected ? 1 : 0.25) : !root.prefix || modelData.hint.indexOf(root.prefix) === 0 ? 1 : 0.25
              Behavior on opacity { NumberAnimation { duration: 60 } }
              ClippingRectangle {
                id: card
                readonly property var handle: root.handleFor(tile.modelData.address)
                width: parent.width
                height: Math.max(1, (tile.modelData.size || [640, 400])[1] * windowGrid.previewScale)
                radius: root.windowRounding
                color: "transparent"
                contentInsideBorder: false
                border.width: tile.selected ? 4 : tile.wasFocused || hover.containsMouse ? 2 : 1
                border.color: tile.selected || tile.wasFocused ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, hover.containsMouse ? 0.65 : 0.3)
                Item {
                  anchors.fill: parent
                  clip: true
                  Image {
                    id: cachedImage
                    anchors.fill: parent
                    readonly property var snapshot: root.cachedPreviews[root.cacheKey(tile.modelData)]
                    source: snapshot ? snapshot.url : ""
                    fillMode: Image.PreserveAspectFit
                    visible: !preview.hasContent
                    cache: false
                    onStatusChanged: {
                      if (status === Image.Ready && !preview.hasContent && root.opened && root.cachedPreviewMs < 0)
                        root.cachedPreviewMs = Date.now() - root.openStartedAt
                    }
                  }
                  ScreencopyView {
                    id: preview
                    property double sourceAssignedAt: 0
                    Component.onCompleted: root.previewCreations++
                    onCaptureSourceChanged: {
                      if (captureSource && root.opened) {
                        sourceAssignedAt = Date.now()
                        if (root.firstCaptureSourceMs < 0) root.firstCaptureSourceMs = sourceAssignedAt - root.openStartedAt
                      }
                    }
                    anchors.fill: parent
                    // Start the focused preview first, instead of allocating all
                    // full-resolution capture buffers in the entrance frame.
                    captureSource: root.captureAddresses.indexOf(tile.modelData.address) !== -1
                      && (root.remainingCapturesEnabled || tile.modelData.address === root.captureAddresses[0]) ? card.handle : null
                    live: root.opened
                    function saveSnapshot() {
                      if (!hasContent || width <= 0 || height <= 0) return
                      var key = root.cacheKey(tile.modelData)
                      var generation = root.snapshotGeneration
                      var scale = Math.min(1, 640 / width, 640 / height)
                      grabToImage(function(result) {
                        root.storeSnapshot(key, result, generation)
                      }, Qt.size(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale))))
                    }
                    Connections {
                      target: root
                      function onSnapshotRequested() { preview.saveSnapshot() }
                    }
                    onHasContentChanged: {
                      if (hasContent && root.opened && !root.remainingCapturesEnabled && !startRemainingCaptures.running)
                        startRemainingCaptures.start()
                      if (hasContent && root.opened && root.firstPreviewMs < 0) {
                        root.firstPreviewMs = Date.now() - root.openStartedAt
                        root.firstCaptureWaitMs = Date.now() - sourceAssignedAt
                      }
                      // Also seed the cache before closing, including with animations off.
                      if (hasContent && root.opened) saveSnapshot()
                    }
                  }
                  FallbackCaption {
                    anchors.centerIn: parent
                    visible: !preview.hasContent && cachedImage.status !== Image.Ready
                    appClass: tile.modelData.class || "Window"
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
            textFormat: Text.PlainText
            visible: root.filteredWindows.length === 0
            text: root.errorText || (listing.running ? "Loading windows…" : root.searchText.trim() ? "No matching windows" : "No windows")
            color: Color.foreground; font.family: Style.font.family
          }
        }
      }
    }
  }
}
