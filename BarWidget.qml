import QtQuick
import Quickshell
import qs.Ui

// Qwitch's per-monitor bar surface. Runtime state belongs to Service.qml;
// this component only renders it, persists inline settings, and hosts the
// one nested panel used by both pointer and shell lifecycle calls.
BarWidget {
  id: root
  moduleName: "io.github.aloglu.qwitch"

  readonly property var service: {
    var shell = root.bar && root.bar.shell ? root.bar.shell : null
    if (!shell || typeof shell.serviceFor !== "function") return null
    return shell.serviceFor(root.moduleName)
  }

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  property var lastSyncedService: null
  property string lastSyncedSettings: ""

  function arrayFrom(value) {
    if (!value || typeof value === "string" || typeof value.length !== "number") return []
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }

  function normalizedSettings(value) {
    var source = value && typeof value === "object" ? value : ({})
    var out = { id: root.moduleName }
    for (var key in source) if (key !== "id") out[key] = source[key]

    out.layouts = arrayFrom(out.layouts)
    if (["text", "flag", "both"].indexOf(String(out.displayMode || "")) === -1)
      out.displayMode = "both"
    out.osdEnabled = out.osdEnabled === true
    if (out.shortcut === undefined) out.shortcut = null
    if (!out.deviceOverrides || typeof out.deviceOverrides !== "object"
        || typeof out.deviceOverrides.length === "number") out.deviceOverrides = ({})
    return out
  }

  function mergedSettings(candidate) {
    var merged = ({})
    var current = root.settings && typeof root.settings === "object" ? root.settings : ({})
    var next = candidate && typeof candidate === "object" ? candidate : ({})
    for (var existing in current) if (existing !== "id") merged[existing] = current[existing]
    for (var key in next) if (key !== "id") merged[key] = next[key]
    return normalizedSettings(merged)
  }

  function pushSettingsToService(value) {
    var target = root.service
    if (!target || typeof target.setSettings !== "function") return false

    var normalized = normalizedSettings(value)
    var serialized = JSON.stringify(normalized)
    if (root.lastSyncedService === target && root.lastSyncedSettings === serialized) return true

    target.setSettings(normalized)
    root.lastSyncedService = target
    root.lastSyncedSettings = serialized
    return true
  }

  function syncServiceSettings() {
    pushSettingsToService(root.settings)
    injectPanel()
  }

  // Settings stay on the widget's shell.json entry. Preserve fields unknown
  // to this UI so future versions do not erase them, update the live widget,
  // persist through the shell, then hand the same value to the singleton.
  function persistSettings(candidate) {
    var merged = mergedSettings(candidate)
    root.settings = merged

    var shell = root.bar && root.bar.shell ? root.bar.shell : null
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(root.moduleName, merged)

    pushSettingsToService(merged)
    injectPanel()
    return true
  }

  function open() {
    if (panelLoader.item && typeof panelLoader.item.open === "function") panelLoader.item.open()
  }

  function openSettings() {
    if (panelLoader.item && typeof panelLoader.item.openSettings === "function")
      panelLoader.item.openSettings()
  }

  function close() {
    if (panelLoader.item && typeof panelLoader.item.close === "function") panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && typeof panelLoader.item.toggle === "function") panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function")
      panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("settings" in target) target.settings = root.settings
    if ("service" in target) target.service = root.service
  }

  function localDisplay(entry, mode) {
    if (!entry || typeof entry !== "object") return ""
    var label = entry.label
      ? String(entry.label) : String(entry.layout || "").toUpperCase()
    var flag = String(entry.flag || "")
    if (mode === "flag") return flag || label
    if (mode === "text") return label || flag
    return flag && label ? flag + " " + label : (flag || label)
  }

  readonly property string displayMode: {
    var mode = root.settings ? String(root.settings.displayMode || "") : ""
    return ["text", "flag", "both"].indexOf(mode) === -1 ? "both" : mode
  }

  readonly property string displayText: {
    if (root.service && root.service.mixedState === true) return "MIXED"
    var entry = root.service && root.service.activeLayout ? root.service.activeLayout : null
    if (!entry) {
      var configured = arrayFrom(root.settings ? root.settings.layouts : [])
      if (configured.length > 0) entry = configured[0]
    }
    if (entry && root.service && typeof root.service.displayTextFor === "function") {
      var rendered = root.service.displayTextFor(entry, root.displayMode)
      if (rendered !== undefined && rendered !== null && String(rendered) !== "")
        return String(rendered)
    }
    return localDisplay(entry, root.displayMode) || "󰌌"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    injectPanel()
    Qt.callLater(root.syncServiceSettings)
  }
  onSettingsChanged: Qt.callLater(root.syncServiceSettings)
  onServiceChanged: {
    root.lastSyncedService = null
    root.lastSyncedSettings = ""
    injectPanel()
    Qt.callLater(root.syncServiceSettings)
  }
  Component.onCompleted: Qt.callLater(root.syncServiceSettings)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    hasVisualContent: text !== ""
    active: root.opened
    tooltipText: root.service && root.service.mixedState === true
      ? "Qwitch: layouts differ across keyboards"
      : "Qwitch — click to switch, right-click for settings"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openSettings()
      else if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
