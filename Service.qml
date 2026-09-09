// Compact top-right control bar on every Hyprland window:
// minimize, maximize, float, close. Right-drag moves the window.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

Item {
  id: service

  property var shell: null

  readonly property int buttonSize: Math.max(18, Style.space(22))
  readonly property int buttonGap: Math.max(2, Style.spacing.xs)
  readonly property int barPad: Math.max(3, Style.spacing.xs)
  readonly property int barInset: Math.max(3, Style.spacing.xs)
  readonly property int barHeight: buttonSize + barPad * 2
  readonly property int barWidth: barPad * 2 + buttonSize * 4 + buttonGap * 3
  readonly property string minimizeWorkspace: "special:omarchy-minimized"
  readonly property string peekWorkspace: "special:omarchy-window-peek"

  property int borderSize: 2
  property color inactiveBorderColor: Color.muted
  property var clients: []
  property var activeWorkspaces: ({})
  property int layoutGen: 0
  property var manifest: null
  property string dragTarget: ""

  readonly property string hookPath: {
    var dir = ""
    if (manifest && manifest.__sourceDir) dir = String(manifest.__sourceDir)
    if (!dir) {
      var url = String(Qt.resolvedUrl("."))
      dir = url.replace(/^file:\/\//, "").replace(/\/$/, "")
    }
    return dir + "/hook.lua"
  }

  readonly property color accentColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)
  readonly property color glyphColor: Color.flatColor(Color.pick("hyprland.active-border-foreground", Color.foreground), Color.foreground)
  readonly property color hoverFill: mixColor(accentColor, Color.background, 0.55)
  readonly property color pressedFill: mixColor(accentColor, Color.background, 0.35)
  readonly property color activeFill: mixColor(accentColor, Color.background, 0.45)

  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  function firstGradientStopColor(raw) {
    var tokens = String(raw || "").trim().split(/\s+/)
    for (var i = 0; i < tokens.length; i++) {
      if (/^[0-9a-fA-F]{8}$/.test(tokens[i])) return "#" + tokens[i]
    }
    return null
  }

  function normalizedAddress(addr) {
    if (addr === undefined || addr === null) return null
    var hex = String(addr)
    if (hex.indexOf("0x") === 0) hex = hex.slice(2)
    return /^[0-9a-fA-F]+$/.test(hex) ? "0x" + hex : null
  }

  function isTruthyFlag(v) {
    return v === true || v === 1 || v === "true"
  }

  function dispatchLua(lua) {
    if (!lua) return
    Quickshell.execDetached(["hyprctl", "dispatch", lua])
  }

  function closeWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    service.dispatchLua("hl.dsp.window.close({ address = \"" + normalized + "\" })")
  }

  function toggleFloat(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    service.dispatchLua("hl.dsp.window.float({ action = \"toggle\", window = \"address:" + normalized + "\" })")
  }

  function toggleMaximize(addr, fullscreen) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    var mode = Number(fullscreen) === 2 ? "fullscreen" : "maximized"
    service.dispatchLua("hl.dsp.window.fullscreen({ mode = \"" + mode + "\", window = \"address:" + normalized + "\" })")
  }

  function minimizeWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    service.dispatchLua("hl.dsp.window.move({ workspace = \"" + service.minimizeWorkspace
      + "\", window = \"address:" + normalized + "\", follow = false })")
  }

  function bringToTop(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    service.dispatchLua("hl.dsp.window.bring_to_top({ window = \"address:" + normalized + "\" })")
  }

  function ensureFloating(addr, currentlyFloating) {
    if (currentlyFloating) return
    service.toggleFloat(addr)
  }

  function moveWindowTo(addr, x, y) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    service.dispatchLua("hl.dsp.window.move({ x = " + Math.round(x) + ", y = " + Math.round(y)
      + ", relative = false, window = \"address:" + normalized + "\" })")
  }

  function workspaceNameOf(entry) {
    if (!entry) return ""
    if (entry.workspace && entry.workspace.name) return String(entry.workspace.name)
    return ""
  }

  function isOnScreen(entry) {
    if (!entry || entry.mapped === false || entry.hidden === true) return false
    if (service.isTruthyFlag(entry.pinned)) return true
    var ws = service.workspaceNameOf(entry)
    if (!ws || ws.indexOf("special:") === 0) return false
    var active = service.activeWorkspaces
    for (var key in active) {
      if (active[key] === ws) return true
    }
    return false
  }

  function focusHistoryId(entry) {
    if (!entry) return 9999
    var n = Number(entry.focusHistoryID)
    if (!isFinite(n)) n = Number(entry.focus_history_id)
    return isFinite(n) ? n : 9999
  }

  function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
  }

  function clientByAddress(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return null
    var list = service.clients
    for (var i = 0; i < list.length; i++) {
      if (service.normalizedAddress(list[i].address) === normalized) return list[i]
    }
    return null
  }

  function zScore(entry) {
    if (!entry) return -99999
    var fs = Number(entry.fullscreen) === 2 ? 2 : 0
    var fl = service.isTruthyFlag(entry.floating) ? 1 : 0
    return fs * 10000 + fl * 1000 - service.focusHistoryId(entry)
  }

  function stackedAbove(other, selfAddr) {
    var self = service.clientByAddress(selfAddr)
    if (!other || !self) return false
    return service.zScore(other) > service.zScore(self)
  }

  function setDragTarget(addr) {
    var normalized = addr ? service.normalizedAddress(addr) : ""
    if (!normalized) normalized = ""
    if (service.dragTarget === normalized) return
    service.dragTarget = normalized
    var path = service.hookPath
    if (!path) return
    var lua = "dofile(" + JSON.stringify(path) + "); window_controls.set_drag_target("
      + (normalized ? JSON.stringify(normalized) : "nil") + ")"
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  // Overlay layers always paint above every client. Hide a bar when an
  // on-screen window stacked above its owner covers that bar's rectangle.
  function barOccluded(selfAddr, barX, barY, barW, barH) {
    var list = service.clients
    var selfNorm = service.normalizedAddress(selfAddr)
    if (!selfNorm) return false
    for (var i = 0; i < list.length; i++) {
      var other = list[i]
      if (!service.isOnScreen(other)) continue
      if (service.normalizedAddress(other.address) === selfNorm) continue
      if (!other.at || other.at.length !== 2 || !other.size || other.size.length !== 2) continue
      if (!service.stackedAbove(other, selfAddr)) continue
      if (service.rectsOverlap(barX, barY, barW, barH, other.at[0], other.at[1], other.size[0], other.size[1]))
        return true
    }
    return false
  }

  function screenForMonitor(monitor) {
    if (!monitor || !monitor.name) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === monitor.name) return screens[i]
    }
    return null
  }

  function workspaceName(modelData, info) {
    if (modelData && modelData.workspace && modelData.workspace.name)
      return String(modelData.workspace.name)
    if (info && info.workspace && info.workspace.name)
      return String(info.workspace.name)
    return ""
  }

  function fullscreenMode(info) {
    if (!info || info.fullscreen === undefined || info.fullscreen === null) return 0
    var n = Number(info.fullscreen)
    return isFinite(n) ? n : 0
  }

  Process {
    id: borderSizeProc
    command: ["hyprctl", "-j", "getoption", "general:border_size"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var n = Number(json.int)
          if (isFinite(n) && n >= 0) service.borderSize = n
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: inactiveBorderProc
    command: ["hyprctl", "-j", "getoption", "general:col.inactive_border"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var color = service.firstGradientStopColor(json.gradient)
          if (color) service.inactiveBorderColor = color
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "[]")
          if (Array.isArray(parsed)) service.clients = parsed
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "[]")
          var map = ({})
          if (Array.isArray(parsed)) {
            for (var i = 0; i < parsed.length; i++) {
              var mon = parsed[i]
              if (mon && mon.name && mon.activeWorkspace && mon.activeWorkspace.name)
                map[mon.name] = String(mon.activeWorkspace.name)
            }
          }
          service.activeWorkspaces = map
        } catch (e) {
        }
      }
    }
  }

  Component.onCompleted: {
    borderSizeProc.running = true
    inactiveBorderProc.running = true
    clientsProc.running = true
    monitorsProc.running = true
  }

  Timer {
    interval: 80
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      Hyprland.refreshToplevels()
      if (!clientsProc.running) clientsProc.running = true
      if (!monitorsProc.running) monitorsProc.running = true
      service.layoutGen++
    }
  }

  Timer {
    id: dragClearTimer
    interval: 1500
    onTriggered: service.setDragTarget("")
  }

  component ControlButton: Item {
    id: btn
    property string kind: "close"
    property bool latched: false
    property bool destructive: false
    readonly property color ink: (tap.pressed && btn.destructive) || (innerHover.hovered && btn.destructive)
      ? Color.background : service.glyphColor
    signal tapped()

    width: service.buttonSize
    height: service.buttonSize

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: {
        if (tap.pressed) return btn.destructive ? Color.urgent : service.pressedFill
        if (innerHover.hovered) return btn.destructive ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.88) : service.hoverFill
        if (btn.latched) return service.activeFill
        return "transparent"
      }
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Item {
      anchors.centerIn: parent
      width: Math.round(parent.width * 0.46)
      height: width

      Rectangle {
        visible: btn.kind === "min"
        width: parent.width
        height: 2
        radius: 1
        anchors.centerIn: parent
        color: btn.ink
      }

      Rectangle {
        visible: btn.kind === "max" && !btn.latched
        anchors.fill: parent
        color: "transparent"
        border.color: btn.ink
        border.width: 2
        radius: 1
      }

      Item {
        visible: btn.kind === "max" && btn.latched
        anchors.fill: parent
        Rectangle {
          width: parent.width * 0.72
          height: width
          x: parent.width * 0.28
          y: 0
          color: "transparent"
          border.color: btn.ink
          border.width: 2
          radius: 1
        }
        Rectangle {
          width: parent.width * 0.72
          height: width
          x: 0
          y: parent.height * 0.28
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.92)
          border.color: btn.ink
          border.width: 2
          radius: 1
        }
      }

      Item {
        visible: btn.kind === "float"
        anchors.fill: parent
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: btn.ink
          border.width: 2
          radius: 1
        }
        Rectangle {
          width: parent.width
          height: 3
          color: btn.ink
        }
      }

      Item {
        visible: btn.kind === "close"
        anchors.fill: parent
        Rectangle {
          width: parent.width * 1.15
          height: 2
          radius: 1
          anchors.centerIn: parent
          rotation: 45
          color: btn.ink
        }
        Rectangle {
          width: parent.width * 1.15
          height: 2
          radius: 1
          anchors.centerIn: parent
          rotation: -45
          color: btn.ink
        }
      }
    }

    HoverHandler {
      id: innerHover
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      id: tap
      acceptedButtons: Qt.LeftButton
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onTapped: btn.tapped()
    }
  }

  Variants {
    model: Hyprland.toplevels.values

    PanelWindow {
      id: chrome
      required property var modelData

      readonly property var info: modelData ? modelData.lastIpcObject : null
      readonly property var snap: service.clientByAddress(modelData ? modelData.address : null)
      readonly property var geo: snap || info
      readonly property var targetScreen: service.screenForMonitor(modelData ? modelData.monitor : null)
      readonly property string wsName: service.workspaceName(modelData, geo)
      readonly property int fsMode: service.fullscreenMode(geo)
      readonly property bool floating: service.isTruthyFlag(geo && geo.floating)
      readonly property bool maximized: fsMode === 1
      readonly property bool shelfHidden: wsName === service.minimizeWorkspace || wsName === service.peekWorkspace
      readonly property bool onScreen: {
        var gen = service.layoutGen
        return !shelfHidden && service.isOnScreen(snap || info)
      }
      readonly property bool geometryOk: !!(onScreen
        && fsMode !== 2
        && geo !== null && geo.mapped !== false && geo.hidden !== true
        && geo.at && geo.at.length === 2 && geo.size && geo.size.length === 2
        && geo.size[0] >= service.barWidth + service.barInset * 2
        && targetScreen !== null)
      readonly property int winX: geometryOk ? geo.at[0] : 0
      readonly property int winY: geometryOk ? geo.at[1] : 0
      readonly property int winW: geometryOk ? geo.size[0] : 0
      readonly property int barLeft: {
        if (!geometryOk) return 0
        var x = winX + winW - targetScreen.x - service.barWidth - service.barInset
        var maxX = Math.max(0, targetScreen.width - service.barWidth)
        return Math.round(Math.max(0, Math.min(x, maxX)))
      }
      readonly property int barTop: {
        if (!geometryOk) return 0
        var y = winY - targetScreen.y + service.barInset
        var maxY = Math.max(0, targetScreen.height - service.barHeight)
        return Math.round(Math.max(0, Math.min(y, maxY)))
      }
      readonly property bool occluded: {
        var gen = service.layoutGen
        var n = service.clients.length
        if (!geometryOk || chrome.dragging) return false
        return service.barOccluded(modelData.address, targetScreen.x + barLeft, targetScreen.y + barTop,
                                   service.barWidth, service.barHeight)
      }
      readonly property bool showable: geometryOk && (!occluded || dragging)
      readonly property bool isActiveWindow: modelData !== null && Hyprland.activeToplevel !== null
        && service.normalizedAddress(Hyprland.activeToplevel.address) === service.normalizedAddress(modelData.address)

      property bool dragging: false
      property real dragHotspotX: 0
      property real dragHotspotY: 0
      property real predX: 0
      property real predY: 0
      property real pendingMoveX: 0
      property real pendingMoveY: 0
      property bool pendingMove: false

      screen: targetScreen
      visible: showable || dragging
      color: "transparent"

      WlrLayershell.namespace: "omarchy-window-controls"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.barWidth
      implicitHeight: service.barHeight

      anchors { left: true; top: true }
      margins.left: dragging && targetScreen
        ? Math.round(Math.max(0, Math.min(predX + winW - targetScreen.x - service.barWidth - service.barInset, targetScreen.width - service.barWidth)))
        : barLeft
      margins.top: dragging && targetScreen
        ? Math.round(Math.max(0, Math.min(predY - targetScreen.y + service.barInset, targetScreen.height - service.barHeight)))
        : barTop

      Timer {
        interval: 16
        running: chrome.pendingMove
        repeat: true
        onTriggered: {
          if (!chrome.pendingMove || !chrome.modelData) {
            chrome.pendingMove = false
            return
          }
          service.moveWindowTo(chrome.modelData.address, chrome.pendingMoveX, chrome.pendingMoveY)
          chrome.pendingMove = false
        }
      }

      Rectangle {
        id: bar
        anchors.fill: parent
        radius: Math.max(6, Math.round(height / 2))
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b,
                       barHover.hovered || chrome.dragging ? 0.96 : (chrome.isActiveWindow ? 0.88 : 0.72))
        border.color: chrome.isActiveWindow || chrome.dragging ? service.accentColor : service.inactiveBorderColor
        border.width: Math.max(1, service.borderSize)

        HoverHandler {
          id: barHover
          cursorShape: chrome.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          onHoveredChanged: {
            if (hovered && chrome.modelData) {
              dragClearTimer.stop()
              service.setDragTarget(chrome.modelData.address)
            } else {
              dragClearTimer.restart()
            }
          }
        }

        MouseArea {
          id: dragArea
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          preventStealing: true
          hoverEnabled: false
          cursorShape: chrome.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          z: 10
          property bool dragMoved: false

          function cursorGlobal(mouse) {
            if (dragArea.mapToGlobal)
              return dragArea.mapToGlobal(mouse.x, mouse.y)
            return Qt.point((chrome.targetScreen ? chrome.targetScreen.x : 0) + chrome.barLeft + mouse.x,
                            (chrome.targetScreen ? chrome.targetScreen.y : 0) + chrome.barTop + mouse.y)
          }

          function buttonAt(px) {
            var total = service.buttonSize * 4 + service.buttonGap * 3
            var start = (width - total) / 2
            var x = px - start
            if (x < 0 || x > total) return -1
            var stride = service.buttonSize + service.buttonGap
            var i = Math.floor(x / stride)
            var inner = x - i * stride
            if (inner > service.buttonSize) return -1
            if (i < 0 || i > 3) return -1
            return i
          }

          onPressed: function(mouse) {
            if (!chrome.geo || !chrome.modelData) return
            if (mouse.button === Qt.RightButton) {
              var g = cursorGlobal(mouse)
              chrome.dragHotspotX = g.x - chrome.winX
              chrome.dragHotspotY = g.y - chrome.winY
              chrome.predX = chrome.winX
              chrome.predY = chrome.winY
              chrome.dragging = true
              dragArea.dragMoved = false
              service.bringToTop(chrome.modelData.address)
              if (chrome.maximized)
                service.toggleMaximize(chrome.modelData.address, chrome.fsMode)
              service.ensureFloating(chrome.modelData.address, chrome.floating)
              var addr = service.normalizedAddress(chrome.modelData.address)
              if (addr)
                service.dispatchLua("hl.dsp.window.drag({ window = \"address:" + addr + "\" })")
              mouse.accepted = true
            }
          }
          onPositionChanged: function(mouse) {
            if (!pressed || !chrome.dragging) return
            var g = cursorGlobal(mouse)
            var nx = g.x - chrome.dragHotspotX
            var ny = g.y - chrome.dragHotspotY
            if (Math.abs(nx - chrome.predX) > 1 || Math.abs(ny - chrome.predY) > 1)
              dragArea.dragMoved = true
            chrome.predX = nx
            chrome.predY = ny
            chrome.pendingMoveX = nx
            chrome.pendingMoveY = ny
            chrome.pendingMove = true
          }
          onReleased: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              if (chrome.pendingMove && chrome.modelData)
                service.moveWindowTo(chrome.modelData.address, chrome.pendingMoveX, chrome.pendingMoveY)
              chrome.pendingMove = false
              chrome.dragging = false
              return
            }
            if (mouse.button === Qt.LeftButton && !chrome.dragging && chrome.modelData) {
              var which = buttonAt(mouse.x)
              if (which === 0) service.minimizeWindow(chrome.modelData.address)
              else if (which === 1) service.toggleMaximize(chrome.modelData.address, chrome.fsMode)
              else if (which === 2) service.toggleFloat(chrome.modelData.address)
              else if (which === 3) service.closeWindow(chrome.modelData.address)
            }
          }
          onCanceled: {
            chrome.pendingMove = false
            chrome.dragging = false
          }
        }

        Row {
          anchors.centerIn: parent
          z: 1
          spacing: service.buttonGap

          ControlButton {
            kind: "min"
            onTapped: service.minimizeWindow(chrome.modelData.address)
          }
          ControlButton {
            kind: "max"
            latched: chrome.maximized
            onTapped: service.toggleMaximize(chrome.modelData.address, chrome.fsMode)
          }
          ControlButton {
            kind: "float"
            latched: chrome.floating
            onTapped: service.toggleFloat(chrome.modelData.address)
          }
          ControlButton {
            kind: "close"
            destructive: true
            onTapped: service.closeWindow(chrome.modelData.address)
          }
        }
      }
    }
  }
}
