// Compact top-right control bar on every Hyprland window:
// minimize, maximize, float, close.
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
    if (typeof addr !== "string") return null
    var hex = addr.indexOf("0x") === 0 ? addr.slice(2) : addr
    return /^[0-9a-fA-F]+$/.test(hex) ? "0x" + hex : null
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

  Component.onCompleted: {
    borderSizeProc.running = true
    inactiveBorderProc.running = true
  }

  Timer {
    interval: 400
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: Hyprland.refreshToplevels()
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
      id: glyph
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
      readonly property var targetScreen: service.screenForMonitor(modelData ? modelData.monitor : null)
      readonly property string wsName: service.workspaceName(modelData, info)
      readonly property int fsMode: service.fullscreenMode(info)
      readonly property bool floating: !!(info && info.floating === true)
      readonly property bool maximized: fsMode === 1
      readonly property bool onActiveWorkspace: modelData !== null && modelData.workspace !== null
        && (modelData.workspace.active === true || (info !== null && info.pinned === true))
      readonly property bool shelfHidden: wsName === service.minimizeWorkspace || wsName === service.peekWorkspace
      readonly property bool showable: !!(onActiveWorkspace
        && !shelfHidden
        && fsMode !== 2
        && info !== null && info.mapped !== false && info.hidden !== true
        && info.at && info.at.length === 2 && info.size && info.size.length === 2
        && info.size[0] >= service.barWidth + service.barInset * 2
        && targetScreen !== null)
      readonly property bool isActiveWindow: modelData !== null && Hyprland.activeToplevel !== null
        && Hyprland.activeToplevel.address === modelData.address

      screen: targetScreen
      visible: showable
      color: "transparent"

      WlrLayershell.namespace: "omarchy-window-controls"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.barWidth
      implicitHeight: service.barHeight

      anchors { left: true; top: true }
      margins.left: {
        if (!showable) return 0
        var x = info.at[0] + info.size[0] - targetScreen.x - service.barWidth - service.barInset
        var maxX = Math.max(0, targetScreen.width - service.barWidth)
        return Math.round(Math.max(0, Math.min(x, maxX)))
      }
      margins.top: {
        if (!showable) return 0
        var y = info.at[1] - targetScreen.y + service.barInset
        var maxY = Math.max(0, targetScreen.height - service.barHeight)
        return Math.round(Math.max(0, Math.min(y, maxY)))
      }

      Rectangle {
        id: bar
        anchors.fill: parent
        radius: Math.max(6, Math.round(height / 2))
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b,
                       barHover.hovered ? 0.96 : (chrome.isActiveWindow ? 0.88 : 0.72))
        border.color: chrome.isActiveWindow ? service.accentColor : service.inactiveBorderColor
        border.width: Math.max(1, service.borderSize)
        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: barHover }

        Row {
          anchors.centerIn: parent
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
