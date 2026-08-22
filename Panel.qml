import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// qwitch's nested panel has two deliberately small surfaces:
//   * the default layout picker
//   * an explicit settings editor opened by right-click or the gear button
// Runtime discovery and switching remain in Service.qml. Settings are kept in
// a local editing value and persisted through Omarchy's native shell API after
// each valid change.
Panel {
  id: root
  moduleName: "io.github.aloglu.qwitch"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.barForeground : Color.foreground
  readonly property color contentAccent: Color.accent
  readonly property color contentUrgent: bar && "urgent" in bar ? bar.urgent : Color.urgent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int settingsFieldHeight: Math.max(
    Style.spacing.controlHeight,
    Math.ceil(settingsFieldMetrics.height) + Style.spacing.inputPaddingY * 2
      + Math.max(Style.normalBorderWidth, Style.hoverBorderWidth,
        Style.focusBorderWidth) * 2)

  TextMetrics {
    id: settingsFieldMetrics
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.subtitle
    text: "English 🇺🇸"
  }

  property bool settingsPage: false
  property int selectorIndex: 0
  property int editingLayoutIndex: -1
  property string selectedCatalogValue: ""
  property bool capturingShortcut: false
  property var recordingChord: []
  property bool recordingSnapshotReady: false
  property var recordingOriginalShortcut: null
  property string recordingOriginalNativeXkbOption: ""
  property string draftError: ""
  property string shortcutError: ""
  property var pendingSecurityDevice: null
  property bool draftReady: false
  property bool advancedDevicesVisible: false
  // Internal aliases used by the native Quickshell integration harness.
  // They also keep geometry/state inspection out of production behavior.
  property alias _settingsViewport: settingsScroll
  property alias _layoutCodeEditor: layoutCodeField
  property alias _variantEditor: variantField
  property alias _shortLabelEditor: shortLabelField
  property alias _flagEditor: flagField
  property alias _displayModeSelector: displayModeGroup
  property alias _layoutScopeSelector: layoutScopeGroup
  property var draft: ({
    layouts: [],
    displayMode: "both",
    osdEnabled: false,
    shortcut: null,
    layoutScope: "global",
    applicationLayouts: ({}),
    deviceOverrides: ({}),
    adoptedExistingConfig: false,
    nativeXkbOption: ""
  })

  function arrayFrom(value) {
    if (!value || typeof value === "string" || typeof value.length !== "number") return []
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }

  function objectFrom(value) {
    return value && typeof value === "object" && typeof value.length !== "number"
      ? value : ({})
  }

  function clone(value, fallback) {
    try {
      if (value === undefined) return fallback
      return JSON.parse(JSON.stringify(value))
    } catch (error) {
      return fallback
    }
  }

  function layoutKey(entry) {
    if (!entry || typeof entry !== "object") return ""
    return String(entry.layout || "").trim() + "\u001f" + String(entry.variant || "").trim()
  }

  function normalizedLayout(entry) {
    var source = entry && typeof entry === "object" ? entry : ({})
    return {
      layout: String(source.layout || "").trim(),
      variant: String(source.variant || "").trim(),
      label: source.label
        ? String(source.label).trim() : String(source.layout || "").trim().toUpperCase(),
      flag: String(source.flag || "").trim()
    }
  }

  function displayFor(entry, mode) {
    if (entry && root.service && typeof root.service.displayTextFor === "function") {
      var rendered = root.service.displayTextFor(entry, mode || "both")
      if (rendered !== undefined && rendered !== null && String(rendered) !== "")
        return String(rendered)
    }
    var item = normalizedLayout(entry)
    var selectedMode = ["text", "flag", "both"].indexOf(String(mode || "")) === -1
      ? "both" : String(mode)
    if (selectedMode === "flag") return item.flag || item.label
    if (selectedMode === "text") return item.label || item.flag
    return item.flag && item.label ? item.flag + " " + item.label : (item.flag || item.label)
  }

  readonly property var selectorLayouts: {
    var live = root.service ? root.arrayFrom(root.service.layouts) : []
    if (live.length > 0) return live
    return root.arrayFrom(root.settings ? root.settings.layouts : [])
  }

  readonly property var draftLayouts: root.arrayFrom(root.draft ? root.draft.layouts : [])
  readonly property var detectedDevices: root.service ? root.arrayFrom(root.service.devices) : []
  readonly property var typingDevices: root.detectedDevices.filter(function(device) {
    return String(device.category || "") === "keyboard"
  })
  readonly property var advancedDevices: root.detectedDevices.filter(function(device) {
    return String(device.category || "") !== "keyboard"
  })
  function prepareDraft() {
    root.draftReady = false
    var source = objectFrom(root.settings)
    var layouts = arrayFrom(source.layouts)

    // Seed from the live service if shell propagation is still catching up.
    if (layouts.length === 0 && root.service) layouts = arrayFrom(root.service.layouts)

    var normalized = []
    for (var i = 0; i < layouts.length; i++) normalized.push(normalizedLayout(layouts[i]))
    var mode = String(source.displayMode || "both")
    if (["text", "flag", "both"].indexOf(mode) === -1) mode = "both"

    root.draft = {
      layouts: normalized,
      displayMode: mode,
      osdEnabled: source.osdEnabled === true,
      shortcut: clone(source.shortcut, null),
      layoutScope: root.layoutScopeFrom(source),
      applicationLayouts: clone(objectFrom(source.applicationLayouts), ({})),
      deviceOverrides: clone(objectFrom(source.deviceOverrides), ({})),
      adoptedExistingConfig: source.adoptedExistingConfig === true,
      nativeXkbOption: source.shortcut ? "" : String(source.nativeXkbOption || "")
    }
    root.editingLayoutIndex = normalized.length > 0 ? 0 : -1
    root.selectedCatalogValue = ""
    root.capturingShortcut = false
    root.recordingChord = []
    root.recordingSnapshotReady = false
    root.recordingOriginalShortcut = null
    root.recordingOriginalNativeXkbOption = ""
    root.pendingSecurityDevice = null
    root.draftError = ""
    root.shortcutError = ""
    root.advancedDevicesVisible = false
    root.draftReady = true
    if (root.service && typeof root.service.refreshCatalog === "function") root.service.refreshCatalog()
    if (root.service && typeof root.service.refreshDevices === "function") root.service.refreshDevices()
  }

  function layoutScopeFrom(source) {
    var value = String(source && source.layoutScope || "")
    if (["global", "application", "window"].indexOf(value) >= 0) return value
    return String(source && source.applicationMode || "") === "remember"
      ? "application" : "global"
  }

  function syncSelectorIndex() {
    var length = root.selectorLayouts.length
    if (length === 0) {
      root.selectorIndex = 0
      return
    }
    var active = root.service ? Number(root.service.activeIndex) : -1
    root.selectorIndex = active >= 0 && active < length
      ? active : Math.max(0, Math.min(root.selectorIndex, length - 1))
  }

  function open() {
    root.settingsPage = false
    root.syncSelectorIndex()
    root.controller.show()
  }

  function openSettings() {
    if (!root.settingsPage) root.prepareDraft()
    root.settingsPage = true
    root.controller.show()
    Qt.callLater(function() {
      settingsScroll.contentY = 0
      settingsScroll.returnToBounds()
      settingsScroll.forceActiveFocus()
    })
  }

  function close() {
    root.capturingShortcut = false
    root.recordingChord = []
    root.recordingSnapshotReady = false
    root.recordingOriginalShortcut = null
    root.recordingOriginalNativeXkbOption = ""
    root.pendingSecurityDevice = null
    root.settingsPage = false
    settingsScroll.contentY = 0
    settingsScroll.returnToBounds()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function cancelSettings() {
    if (autoSaveTimer.running) {
      autoSaveTimer.stop()
      root.saveSettings()
    }
    root.capturingShortcut = false
    root.recordingChord = []
    root.recordingSnapshotReady = false
    root.recordingOriginalShortcut = null
    root.recordingOriginalNativeXkbOption = ""
    root.pendingSecurityDevice = null
    root.settingsPage = false
    settingsScroll.contentY = 0
    settingsScroll.returnToBounds()
    root.syncSelectorIndex()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function moveSelector(delta) {
    var count = root.selectorLayouts.length
    if (count === 0) return
    root.selectorIndex = (root.selectorIndex + delta + count) % count
  }

  function chooseLayout(index) {
    if (!root.service || typeof root.service.switchTo !== "function") {
      root.draftError = "qwitch service is not available."
      return
    }
    if (index < 0 || index >= root.selectorLayouts.length) return
    var accepted = root.service.switchTo(index)
    if (accepted !== false) root.close()
  }

  function layoutAt(index) {
    return index >= 0 && index < root.draftLayouts.length
      ? root.draftLayouts[index] : ({ layout: "", variant: "", label: "", flag: "" })
  }

  function replaceLayouts(layouts, selectedIndex) {
    root.draft = {
      layouts: layouts,
      displayMode: String(root.draft.displayMode || "both"),
      osdEnabled: root.draft.osdEnabled === true,
      shortcut: clone(root.draft.shortcut, null),
      layoutScope: String(root.draft.layoutScope || "global"),
      applicationLayouts: clone(objectFrom(root.draft.applicationLayouts), ({})),
      deviceOverrides: clone(objectFrom(root.draft.deviceOverrides), ({})),
      adoptedExistingConfig: root.draft.adoptedExistingConfig === true,
      nativeXkbOption: root.draft.shortcut ? "" : String(root.draft.nativeXkbOption || "")
    }
    root.editingLayoutIndex = selectedIndex
    root.draftError = ""
    root.scheduleAutoSave()
  }

  function updateLayout(index, field, value) {
    var layouts = clone(root.draftLayouts, [])
    if (index < 0 || index >= layouts.length) return
    var next = normalizedLayout(layouts[index])
    next[field] = String(value || "").trim()
    layouts[index] = next
    replaceLayouts(layouts, index)
  }

  function moveLayout(index, delta) {
    var layouts = clone(root.draftLayouts, [])
    var target = index + delta
    if (index < 0 || index >= layouts.length || target < 0 || target >= layouts.length) return
    var item = layouts[index]
    layouts.splice(index, 1)
    layouts.splice(target, 0, item)
    replaceLayouts(layouts, target)
  }

  function removeLayout(index) {
    var layouts = clone(root.draftLayouts, [])
    if (index < 0 || index >= layouts.length) return
    layouts.splice(index, 1)
    var next = layouts.length === 0 ? -1 : Math.min(index, layouts.length - 1)
    replaceLayouts(layouts, next)
  }

  function catalogOptionsFor(value) {
    var entries = arrayFrom(value)
    var out = []
    var seen = ({})
    for (var i = 0; i < entries.length; i++) {
      var raw = entries[i]
      var source = raw && typeof raw === "object" ? raw : ({ layout: String(raw || "") })
      var layout = String(source.layout || source.code || source.name || source.value || "").trim()
      var variant = String(source.variant || "").trim()
      if (!layout) continue
      var key = layout + "\u001f" + variant
      if (seen[key]) continue
      seen[key] = true
      var human = String(source.description || source.label || layout).trim()
      var title = variant ? human + " — " + variant : human
      out.push({
        value: key,
        label: title,
        description: variant ? layout + " (" + variant + ")" : layout,
        layout: layout,
        variant: variant,
        shortLabel: String(source.shortLabel || source.abbreviation || source.brief
          || source.label || layout).trim().toUpperCase(),
        flag: String(source.flag || "").trim()
      })
    }
    return out
  }

  readonly property var catalogOptions: catalogOptionsFor(service ? service.catalog : [])

  function catalogEntry(value) {
    var options = root.catalogOptions
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return options[i]
    return null
  }

  function addSelectedCatalogLayout() {
    var selected = catalogEntry(root.selectedCatalogValue)
    if (!selected) {
      root.draftError = "Choose a keyboard layout to add."
      return
    }
    var entry = {
      layout: selected.layout,
      variant: selected.variant,
      label: selected.shortLabel,
      flag: selected.flag
    }
    var layouts = clone(root.draftLayouts, [])
    var key = layoutKey(entry)
    for (var i = 0; i < layouts.length; i++) {
      if (layoutKey(layouts[i]) === key) {
        root.editingLayoutIndex = i
        root.draftError = "That layout and variant are already in the list."
        return
      }
    }
    layouts.push(entry)
    replaceLayouts(layouts, layouts.length - 1)
    root.selectedCatalogValue = ""
  }

  function setDraftValue(key, value) {
    var next = clone(root.draft, ({}))
    next[key] = value
    root.draft = next
    root.draftError = ""
    root.scheduleAutoSave()
  }

  function scheduleAutoSave() {
    if (root.draftReady) autoSaveTimer.restart()
  }

  function deviceFingerprint(device) {
    if (!device || typeof device !== "object") return ""
    return String(device.fingerprint || "")
  }

  function deviceLabel(device) {
    if (!device || typeof device !== "object") return "Unknown input device"
    return String(device.label || device.name || device.fingerprint || "Unknown input device")
  }

  function deviceOverrideValue(device) {
    var fingerprint = deviceFingerprint(device)
    var overrides = objectFrom(root.draft.deviceOverrides)
    // The draft is authoritative while settings are open. In particular,
    // removing a saved override must render as Auto before the debounce fires.
    var explicitValue = String(overrides[fingerprint] || "auto")
    return ["auto", "manage", "ignore"].indexOf(explicitValue) === -1 ? "auto" : explicitValue
  }

  function setDeviceOverride(device, value) {
    var fingerprint = deviceFingerprint(device)
    if (!fingerprint) return
    var old = objectFrom(root.draft.deviceOverrides)
    var overrides = ({})
    for (var key in old) if (key !== fingerprint) overrides[key] = old[key]
    if (value === "manage" || value === "ignore") overrides[fingerprint] = value
    setDraftValue("deviceOverrides", overrides)
    root.pendingSecurityDevice = null
  }

  function requestDeviceOverride(device, value) {
    if (value === "manage" && device && device.security === true) {
      root.pendingSecurityDevice = device
      return
    }
    setDeviceOverride(device, value)
  }

  function isPendingSecurityDevice(device) {
    return root.pendingSecurityDevice
      && deviceFingerprint(root.pendingSecurityDevice) === deviceFingerprint(device)
  }

  function shortcutSummary(shortcut) {
    if (!shortcut) return "Not assigned"
    if (typeof shortcut === "string") return shortcut || "Not assigned"
    var parts = arrayFrom(shortcut.modifiers)
    var key = String(shortcut.key || shortcut.name || "")
    if (key) parts.push(key)
    return parts.length > 0 ? parts.join(" + ") : "Not assigned"
  }

  function displayedShortcut() {
    if (root.draft.shortcut) return root.shortcutSummary(root.draft.shortcut)
    var nativeLabel = root.nativeShortcutSummary()
    return nativeLabel || "Not assigned"
  }

  function nativeShortcutSummary() {
    var nativeOption = String(root.draft.nativeXkbOption || "")
    if (!nativeOption && root.service)
      return String(root.service.nativeShortcutLabel || "")
    if (!nativeOption) return ""
    var label = String(Model.nativeXkbShortcutLabel(nativeOption) || "")
    return label || nativeOption
  }

  function chooseNativeShortcut(option) {
    root.capturingShortcut = false
    root.recordingChord = []
    root.recordingSnapshotReady = false
    root.shortcutError = ""
    var next = clone(root.draft, ({}))
    next.shortcut = null
    next.nativeXkbOption = String(option || "")
    root.draft = next
    root.scheduleAutoSave()
  }

  function chooseRecordedShortcut(shortcut) {
    root.recordingChord = []
    root.recordingSnapshotReady = false
    var next = clone(root.draft, ({}))
    next.shortcut = clone(shortcut, null)
    next.nativeXkbOption = ""
    root.draft = next
    root.scheduleAutoSave()
  }

  function isModifierKey(key) {
    return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Meta
      || key === Qt.Key_Alt || key === Qt.Key_AltGr || key === Qt.Key_CapsLock
  }

  function chordParts(event) {
    var parts = []
    if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
    if (event.modifiers & Qt.AltModifier) parts.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT")
    if (event.key === Qt.Key_Meta && parts.indexOf("SUPER") === -1) parts.push("SUPER")
    if (event.key === Qt.Key_Control && parts.indexOf("CTRL") === -1) parts.push("CTRL")
    if ((event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)
        && parts.indexOf("ALT") === -1) parts.push("ALT")
    if (event.key === Qt.Key_Shift && parts.indexOf("SHIFT") === -1) parts.push("SHIFT")
    if (event.key === Qt.Key_CapsLock) parts.push("CAPSLOCK")
    if (event.key === Qt.Key_Space) parts.push("SPACE")
    if (event.key === Qt.Key_Menu) parts.push("MENU")
    if (event.key === Qt.Key_ScrollLock) parts.push("SCROLLLOCK")
    return parts
  }

  function mergedChordParts(parts, event) {
    var merged = Array.isArray(parts) ? parts.slice() : []
    var current = chordParts(event)
    for (var i = 0; i < current.length; i++) {
      if (merged.indexOf(current[i]) === -1) merged.push(current[i])
    }
    return merged
  }

  function snapshotShortcutRecording() {
    root.recordingOriginalShortcut = clone(root.draft.shortcut, null)
    root.recordingOriginalNativeXkbOption = String(root.draft.nativeXkbOption || "")
    root.recordingSnapshotReady = true
  }

  function beginShortcutRecording() {
    if (autoSaveTimer.running) {
      autoSaveTimer.stop()
      root.saveSettings()
    }
    root.snapshotShortcutRecording()
    root.recordingChord = []
    root.shortcutError = ""
    root.capturingShortcut = true
    Qt.callLater(function() { shortcutField.forceActiveFocus() })
  }

  function cancelShortcutRecording() {
    root.restoreRejectedShortcut("")
  }

  function restoreRejectedShortcut(message) {
    if (root.recordingSnapshotReady) {
      var restored = clone(root.draft, ({}))
      restored.shortcut = clone(root.recordingOriginalShortcut, null)
      restored.nativeXkbOption = root.recordingOriginalNativeXkbOption
      root.draft = restored
    }
    root.capturingShortcut = false
    root.recordingChord = []
    root.recordingSnapshotReady = false
    root.recordingOriginalShortcut = null
    root.recordingOriginalNativeXkbOption = ""
    root.shortcutError = String(message || "")
  }

  function finishModifierShortcut(event) {
    if (!root.capturingShortcut || !root.isModifierKey(event.key)
        || root.recordingChord.length === 0) return
    var nativeOption = Model.nativeXkbOptionForChord(root.recordingChord)
    if (nativeOption) {
      root.chooseNativeShortcut(nativeOption)
    } else {
      root.restoreRejectedShortcut("That modifier-only combination is not available as a native XKB layout shortcut. Record a supported modifier combination or include a non-modifier key.")
    }
    event.accepted = true
  }

  function keyName(event) {
    var key = Number(event.key)
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + String(key - Qt.Key_F1 + 1)
    if (key === Qt.Key_Space) return "Space"
    if (key === Qt.Key_Escape) return "Escape"
    if (key === Qt.Key_Tab) return "Tab"
    if (key === Qt.Key_Backtab) return "Backtab"
    if (key === Qt.Key_Return || key === Qt.Key_Enter) return "Enter"
    if (key === Qt.Key_Backspace) return "Backspace"
    if (key === Qt.Key_Delete) return "Delete"
    if (key === Qt.Key_Insert) return "Insert"
    if (key === Qt.Key_Home) return "Home"
    if (key === Qt.Key_End) return "End"
    if (key === Qt.Key_PageUp) return "PageUp"
    if (key === Qt.Key_PageDown) return "PageDown"
    if (key === Qt.Key_Left) return "Left"
    if (key === Qt.Key_Right) return "Right"
    if (key === Qt.Key_Up) return "Up"
    if (key === Qt.Key_Down) return "Down"
    if (key === Qt.Key_Print) return "Print"
    if (key === Qt.Key_Pause) return "Pause"
    if (key === Qt.Key_VolumeMute) return "VolumeMute"
    if (key === Qt.Key_VolumeDown) return "VolumeDown"
    if (key === Qt.Key_VolumeUp) return "VolumeUp"
    if (key === Qt.Key_MediaPlay) return "MediaPlay"
    if (key === Qt.Key_MediaPause) return "MediaPause"
    if (key === Qt.Key_MediaStop) return "MediaStop"
    if (key === Qt.Key_MediaPrevious) return "MediaPrevious"
    if (key === Qt.Key_MediaNext) return "MediaNext"
    if (key === Qt.Key_MonBrightnessDown) return "MonBrightnessDown"
    if (key === Qt.Key_MonBrightnessUp) return "MonBrightnessUp"
    if (key === Qt.Key_KeyboardBrightnessDown) return "KbdBrightnessDown"
    if (key === Qt.Key_KeyboardBrightnessUp) return "KbdBrightnessUp"
    if (event.text && String(event.text).trim() !== "") return String(event.text).toUpperCase()
    return "Key 0x" + key.toString(16).toUpperCase()
  }

  function recordShortcut(event) {
    if (!root.capturingShortcut) return
    if (!root.recordingSnapshotReady) root.snapshotShortcutRecording()
    if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
      root.cancelShortcutRecording()
      event.accepted = true
      return
    }
    if (isModifierKey(event.key)) {
      root.recordingChord = mergedChordParts(root.recordingChord, event)
      root.shortcutError = "Release the keys to record this native modifier shortcut."
      event.accepted = true
      return
    }

    var parts = mergedChordParts(root.recordingChord, event)
    var nativeOption = Model.nativeXkbOptionForChord(parts)
    if (nativeOption) {
      chooseNativeShortcut(nativeOption)
      event.accepted = true
      return
    }
    var modifiers = parts.filter(function(part) {
      return ["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(part) !== -1
    })

    var shortcut = {
      modifiers: modifiers,
      key: keyName(event),
      code: Number(event.nativeScanCode || 0)
    }
    var error = root.service && typeof root.service.validateShortcut === "function"
      ? String(root.service.validateShortcut(shortcut) || "") : ""
    if (error) {
      root.shortcutError = error
    } else {
      chooseRecordedShortcut(shortcut)
      root.shortcutError = ""
      root.capturingShortcut = false
    }
    event.accepted = true
  }

  function validateDraft() {
    var layouts = root.draftLayouts
    var maximumLayouts = root.service && Number(root.service.maximumLayouts) > 0
      ? Number(root.service.maximumLayouts) : 16
    if (layouts.length > maximumLayouts)
      return "qwitch supports at most " + maximumLayouts + " layouts."
    if (layouts.length === 0 && root.draft.shortcut)
      return "Add a layout before assigning a shortcut."
    var seen = ({})
    for (var i = 0; i < layouts.length; i++) {
      var entry = normalizedLayout(layouts[i])
      var validated = Model.normalizeLayoutEntry(entry)
      if (!validated)
        return "Use a valid XKB layout and variant name."
      if (root.catalogOptions.length > 0 && !root.catalogEntry(root.layoutKey(validated)))
        return "That XKB layout and variant are not available on this system."
      var key = layoutKey(entry)
      if (seen[key]) return "Each layout and variant combination must be unique."
      seen[key] = true
    }
    if (root.draft.shortcut && root.service && typeof root.service.validateShortcut === "function") {
      var shortcutValidation = String(root.service.validateShortcut(root.draft.shortcut) || "")
      if (shortcutValidation) return shortcutValidation
    }
    return ""
  }

  function saveSettings() {
    var validation = validateDraft()
    if (validation) {
      root.draftError = validation
      return
    }
    if (!root.hostWidget || typeof root.hostWidget.persistSettings !== "function") {
      root.draftError = "The qwitch bar widget is not available to save settings."
      return
    }

    var layouts = []
    for (var i = 0; i < root.draftLayouts.length; i++) {
      var normalized = Model.normalizeLayoutEntry(normalizedLayout(root.draftLayouts[i]))
      if (normalized) layouts.push(normalized)
    }
    var candidate = {
      layouts: layouts,
      displayMode: String(root.draft.displayMode || "both"),
      osdEnabled: root.draft.osdEnabled === true,
      shortcut: clone(root.draft.shortcut, null),
      layoutScope: String(root.draft.layoutScope || "global"),
      applicationLayouts: Model.sanitizeApplicationLayouts(
        root.draft.applicationLayouts, layouts),
      deviceOverrides: clone(objectFrom(root.draft.deviceOverrides), ({})),
      adoptedExistingConfig: true,
      nativeXkbOption: root.draft.shortcut ? "" : String(root.draft.nativeXkbOption || "")
    }

    root.hostWidget.persistSettings(candidate)
    root.draft = clone(candidate, candidate)
    root.draftError = ""
  }

  Timer {
    id: autoSaveTimer
    interval: 450
    repeat: false
    onTriggered: root.saveSettings()
  }

  onServiceChanged: {
    if (!root.settingsPage) root.syncSelectorIndex()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.settingsPage ? settingsScroll : keyCatcher
    contentWidth: panel.fittedContentWidth(root.settingsPage ? Style.space(430) : Style.space(320))
    contentHeight: panel.fittedContentHeight(
      root.settingsPage ? Style.space(650) : selectorPage.implicitHeight,
      Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsPage
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelector(dy)
      }
      onActivateRequested: root.chooseLayout(root.selectorIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "s" || text === "S" || text === ",") root.openSettings()
      }

      Column {
        id: selectorPage
        visible: !root.settingsPage
        width: parent.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Math.max(mainTitle.implicitHeight, settingsButton.implicitHeight)

          Text {
            id: mainTitle
            anchors.left: parent.left
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "qwitch: Layouts"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          PanelActionButton {
            id: settingsButton
            iconText: "󰒓"
            tooltipText: "qwitch settings"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            focusable: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.openSettings()
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        Text {
          visible: root.selectorLayouts.length === 0
          width: parent.width
          text: "No layouts are configured. Open settings to add one."
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.selectorLayouts.length > 0
            && root.service && root.service.configuredLayouts.length === 0
          width: parent.width
          text: "Adopting the active Hyprland layouts…"
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Flickable {
          id: layoutPickerScroll
          visible: root.selectorLayouts.length > 0
          width: parent.width
          height: Math.min(layoutPickerColumn.implicitHeight, Style.space(360))
          contentWidth: width
          contentHeight: layoutPickerColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: layoutPickerColumn
            width: layoutPickerScroll.width
            spacing: Style.space(4)

            Repeater {
              model: root.selectorLayouts

              delegate: Button {
                required property var modelData
                required property int index
                width: layoutPickerColumn.width
                text: root.displayFor(modelData, "both")
                iconText: root.service && root.service.activeIndex === index
                  && root.service.mixedState !== true ? "󰄬" : ""
                leftAlign: true
                bordered: true
                selected: root.service && root.service.activeIndex === index
                  && root.service.mixedState !== true
                hasCursor: root.selectorIndex === index
                enabled: root.service && root.service.canSwitch === true
                foreground: root.contentForeground
                accent: root.contentAccent
                fontFamily: root.contentFontFamily
                onHovered: function(isHovered) {
                  if (isHovered) root.selectorIndex = index
                }
                onClicked: root.chooseLayout(index)
              }
            }
          }
        }

        Text {
          visible: root.service && String(root.service.lastError || "") !== ""
          width: parent.width
          text: root.service ? String(root.service.lastError || "") : ""
          color: root.contentUrgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Flickable {
        id: settingsScroll
        objectName: "settingsScroll"
        visible: root.settingsPage
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Keys.priority: Keys.AfterItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancelSettings()
            event.accepted = true
          }
        }

        Column {
          id: settingsColumn
          width: settingsScroll.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "qwitch: Settings"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          PanelSeparator { foreground: root.contentForeground }
          PanelSectionHeader {
            text: "󰌌  LAYOUTS"
            foreground: root.contentAccent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.body
          }

          Text {
            width: parent.width
            text: "Choose a layout to add it immediately. Drag-free arrows control switch order."
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Item {
            width: parent.width
            height: Style.spacing.controlHeight

            SearchableDropdown {
              id: catalogDropdown
              anchors.left: parent.left
              anchors.right: refreshCatalogButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              showLabel: false
              options: root.catalogOptions
              value: root.selectedCatalogValue
              triggerLabel: root.service && root.service.catalogLoading === true
                ? "Loading layouts…" : "Choose a layout…"
              placeholderText: "Search XKB layouts…"
              emptyText: root.service && root.service.catalogLoading === true
                ? "Loading…" : "No layouts found"
              foreground: root.contentForeground
              accent: root.contentAccent
              fontFamily: root.contentFontFamily
              onChanged: function(value) {
                root.selectedCatalogValue = value
                root.addSelectedCatalogLayout()
              }
            }

            PanelActionButton {
              id: refreshCatalogButton
              iconText: "󰑐"
              tooltipText: "Refresh layout catalogue"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              focusable: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              enabled: !(root.service && root.service.catalogLoading === true)
              onClicked: if (root.service && typeof root.service.refreshCatalog === "function")
                root.service.refreshCatalog()
            }

          }

          Text {
            visible: root.service && String(root.service.catalogError || "") !== ""
            width: parent.width
            text: root.service ? String(root.service.catalogError || "") : ""
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.draftLayouts.length === 0
            width: parent.width
            text: "No layouts configured. Choose one above to enable switching."
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.draftLayouts

            delegate: Item {
              required property var modelData
              required property int index
              width: settingsColumn.width
              height: Style.spacing.controlHeight

              Button {
                anchors.left: parent.left
                anchors.right: moveUpButton.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                text: root.displayFor(modelData, "both")
                  + (String(modelData.variant || "") ? " · " + String(modelData.variant) : "")
                leftAlign: true
                bordered: true
                selected: root.editingLayoutIndex === index
                focusable: true
                foreground: root.contentForeground
                accent: root.contentAccent
                fontFamily: root.contentFontFamily
                onClicked: root.editingLayoutIndex = index
              }

              PanelActionButton {
                id: moveUpButton
                iconText: "󰁝"
                tooltipText: "Move up"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                focusable: true
                enabled: index > 0
                anchors.right: moveDownButton.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.moveLayout(index, -1)
              }

              PanelActionButton {
                id: moveDownButton
                iconText: "󰁅"
                tooltipText: "Move down"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                focusable: true
                enabled: index < root.draftLayouts.length - 1
                anchors.right: removeButton.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.moveLayout(index, 1)
              }

              PanelActionButton {
                id: removeButton
                iconText: "󰅙"
                tooltipText: "Remove layout"
                foreground: root.contentForeground
                hoverColor: root.contentUrgent
                fontFamily: root.contentFontFamily
                focusable: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.removeLayout(index)
              }
            }
          }

          Column {
            visible: root.editingLayoutIndex >= 0
              && root.editingLayoutIndex < root.draftLayouts.length
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: root.editingLayoutIndex >= 0
                ? "Edit " + root.displayFor(root.layoutAt(root.editingLayoutIndex), "both") : ""
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(6)
              readonly property real fieldWidth: (width - columnSpacing) / 2

              Column {
                width: parent.fieldWidth
                spacing: Style.space(3)
                Text {
                  text: "Layout code  󰋼"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  HoverHandler { id: layoutCodeHelp }
                  PanelToolTip {
                    visible: layoutCodeHelp.hovered
                    text: "The XKB code, such as us, tr, de, or gb."
                    fontFamily: root.contentFontFamily
                  }
                }
                TextField {
                  id: layoutCodeField
                  objectName: "layoutCodeField"
                  width: parent.width
                  height: root.settingsFieldHeight
                  text: root.layoutAt(root.editingLayoutIndex).layout
                  placeholderText: "us"
                  foreground: root.contentForeground
                  accent: root.contentAccent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  activeFocusOnPress: true
                  onTextEdited: root.updateLayout(root.editingLayoutIndex, "layout", text)
                }
              }

              Column {
                width: parent.fieldWidth
                spacing: Style.space(3)
                Text {
                  text: "Variant  󰋼"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  HoverHandler { id: variantHelp }
                  PanelToolTip {
                    visible: variantHelp.hovered
                    text: "An optional XKB variation, such as intl or nodeadkeys."
                    fontFamily: root.contentFontFamily
                  }
                }
                TextField {
                  id: variantField
                  objectName: "variantField"
                  width: parent.width
                  height: root.settingsFieldHeight
                  text: root.layoutAt(root.editingLayoutIndex).variant
                  placeholderText: "Optional"
                  foreground: root.contentForeground
                  accent: root.contentAccent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  activeFocusOnPress: true
                  onTextEdited: root.updateLayout(root.editingLayoutIndex, "variant", text)
                }
              }
              Column {
                width: parent.fieldWidth
                spacing: Style.space(3)
                Text {
                  text: "Short label  󰋼"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  HoverHandler { id: shortLabelHelp }
                  PanelToolTip {
                    visible: shortLabelHelp.hovered
                    text: "The compact name shown in the bar, for example EN or TR."
                    fontFamily: root.contentFontFamily
                  }
                }
                TextField {
                  id: shortLabelField
                  objectName: "shortLabelField"
                  width: parent.width
                  height: root.settingsFieldHeight
                  text: root.layoutAt(root.editingLayoutIndex).label
                  placeholderText: "EN"
                  foreground: root.contentForeground
                  accent: root.contentAccent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  activeFocusOnPress: true
                  onTextEdited: root.updateLayout(root.editingLayoutIndex, "label", text)
                }
              }

              Column {
                width: parent.fieldWidth
                spacing: Style.space(3)
                Text {
                  text: "Flag emoji  󰋼"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  HoverHandler { id: flagHelp }
                  PanelToolTip {
                    visible: flagHelp.hovered
                    text: "Optional. Used when the display mode includes a flag."
                    fontFamily: root.contentFontFamily
                  }
                }
                TextField {
                  id: flagField
                  objectName: "flagField"
                  width: parent.width
                  height: root.settingsFieldHeight
                  text: root.layoutAt(root.editingLayoutIndex).flag
                  placeholderText: "🇺🇸"
                  foreground: root.contentForeground
                  accent: root.contentAccent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  activeFocusOnPress: true
                  onTextEdited: root.updateLayout(root.editingLayoutIndex, "flag", text)
                }
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }
          PanelSectionHeader {
            text: "󰍹  APPEARANCE"
            foreground: root.contentAccent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.body
          }

          Item {
            width: parent.width
            height: Math.max(displayModeLabel.implicitHeight, displayModeGroup.implicitHeight)

            Text {
              id: displayModeLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Bar display"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            ButtonGroup {
              id: displayModeGroup
              objectName: "displayModeGroup"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: [
                { value: "text", label: "Text" },
                { value: "flag", label: "Flag" },
                { value: "both", label: "Both" }
              ]
              value: String(root.draft.displayMode || "both")
              foreground: root.contentForeground
              accent: root.contentAccent
              fontFamily: root.contentFontFamily
              onChanged: function(value) { root.setDraftValue("displayMode", value) }
            }

          }

          Item {
            width: parent.width
            height: Math.max(osdLabel.implicitHeight, osdSwitch.implicitHeight)

            Text {
              id: osdLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Show all layout changes on OSD  󰋼"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              HoverHandler { id: osdHelp }
              PanelToolTip {
                visible: osdHelp.hovered
                text: "Show every layout change, including automatic app and window restores, through Omarchy’s on-screen display."
                fontFamily: root.contentFontFamily
              }
            }

            ToggleSwitch {
              id: osdSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.draft.osdEnabled === true
              trackHeight: Style.space(18)
              cursorRing: false
              foreground: root.contentForeground
              accent: root.contentAccent
              onToggled: root.setDraftValue("osdEnabled", !root.draft.osdEnabled)
            }
          }

          PanelSeparator { foreground: root.contentForeground }
          PanelSectionHeader {
            text: "󰖲  LAYOUT SCOPE"
            foreground: root.contentAccent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.body
          }

          ButtonGroup {
            id: layoutScopeGroup
            width: parent.width
            options: [
              { value: "global", label: "Global" },
              { value: "application", label: "Per app" },
              { value: "window", label: "Per window" }
            ]
            value: String(root.draft.layoutScope || "global")
            foreground: root.contentForeground
            accent: root.contentAccent
            fontFamily: root.contentFontFamily
            onChanged: function(value) { root.setDraftValue("layoutScope", value) }
          }

          Text {
            width: parent.width
            text: String(root.draft.layoutScope || "global") === "window"
              ? "Each open window keeps its own layout until that window closes or the shell restarts."
              : String(root.draft.layoutScope || "global") === "application"
                ? "Every window belonging to an application shares its remembered layout."
                : "One active layout is shared globally across all applications."
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.contentForeground }
          PanelSectionHeader {
            text: "󰌌  SWITCHING SHORTCUT"
            foreground: root.contentAccent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.body
          }

          Text {
            width: parent.width
            text: "Layout shortcut"
            color: Qt.darker(root.contentForeground, 1.25)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            width: parent.width
            text: "Record a key combination. Supported modifier-only chords use native XKB automatically."
            color: Qt.darker(root.contentForeground, 1.35)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Item {
            width: parent.width
            height: Style.spacing.controlHeight

            TextField {
              id: shortcutField
              anchors.left: parent.left
              anchors.right: recordShortcutButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              readOnly: true
              text: root.capturingShortcut
                ? "Press a key combination…" : root.displayedShortcut()
              foreground: root.contentForeground
              accent: root.contentAccent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) { root.recordShortcut(event) }
              Keys.onReleased: function(event) { root.finishModifierShortcut(event) }
            }

            Button {
              id: recordShortcutButton
              text: root.capturingShortcut ? "Cancel" : "Record"
              bordered: true
              focusable: true
              foreground: root.contentForeground
              accent: root.contentAccent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.subtitle
              height: parent.height
              anchors.right: clearShortcutButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (root.capturingShortcut) root.cancelShortcutRecording()
                else root.beginShortcutRecording()
              }
            }

            PanelActionButton {
              id: clearShortcutButton
              iconText: "󰅙"
              tooltipText: "Clear shortcut"
              foreground: root.contentForeground
              hoverColor: root.contentUrgent
              fontFamily: root.contentFontFamily
              focusable: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              enabled: (root.draft.shortcut !== null && root.draft.shortcut !== undefined)
                || String(root.draft.nativeXkbOption || "") !== ""
              onClicked: {
                root.capturingShortcut = false
                root.shortcutError = ""
                root.chooseNativeShortcut("")
              }
            }
          }

          Text {
            visible: root.shortcutError !== ""
            width: parent.width
            text: root.shortcutError
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.service && root.service.shortcutConflict
              && String(root.service.shortcutConflict) !== ""
            width: parent.width
            text: root.service ? String(root.service.shortcutConflict || "") : ""
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.contentForeground }
          Row {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              width: Math.max(0, parent.width - refreshDevicesButton.implicitWidth - parent.spacing)
              text: "󰌓  KEYBOARDS"
              foreground: root.contentAccent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.body
            }

            PanelActionButton {
              id: refreshDevicesButton
              iconText: "󰑐"
              tooltipText: "Refresh input devices"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              focusable: true
              onClicked: if (root.service && typeof root.service.refreshDevices === "function")
                root.service.refreshDevices()
            }
          }

          Text {
            visible: root.typingDevices.length === 0
            width: parent.width
            text: "No high-confidence typing keyboard was detected. Open advanced devices to inspect what Hyprland reported."
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.typingDevices.length > 0
            width: parent.width
            text: "qwitch manages " + root.typingDevices.length
              + (root.typingDevices.length === 1 ? " typing keyboard automatically." : " typing keyboards automatically.")
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Component {
            id: deviceEditorDelegate

            Column {
              required property var modelData
              required property int index
              readonly property bool advancedEntry:
                String(modelData.category || "") !== "keyboard"
              width: settingsColumn.width
              spacing: Style.space(5)

              Text {
                width: parent.width
                text: root.deviceLabel(modelData)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: String(modelData.reason || "") !== ""
                width: parent.width
                text: String(modelData.reason || "")
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              ButtonGroup {
                options: [
                  { value: "auto", label: "Auto" },
                  { value: "manage", label: "Manage" },
                  { value: "ignore", label: "Ignore" }
                ]
                value: root.deviceOverrideValue(modelData)
                enabled: root.deviceFingerprint(modelData) !== ""
                foreground: root.contentForeground
                accent: root.contentAccent
                fontFamily: root.contentFontFamily
                onChanged: function(value) { root.requestDeviceOverride(modelData, value) }
              }

              Text {
                visible: root.isPendingSecurityDevice(modelData)
                width: parent.width
                text: "This device is identified as a security token. Managing it can interfere with OTP or FIDO input."
                color: root.contentUrgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Row {
                visible: root.isPendingSecurityDevice(modelData)
                spacing: Style.space(6)

                Button {
                  text: "Manage anyway"
                  bordered: true
                  focusable: true
                  foreground: root.contentUrgent
                  accent: root.contentUrgent
                  fontFamily: root.contentFontFamily
                  onClicked: root.setDeviceOverride(modelData, "manage")
                }

                Button {
                  text: "Keep automatic"
                  bordered: true
                  focusable: true
                  foreground: root.contentForeground
                  accent: root.contentAccent
                  fontFamily: root.contentFontFamily
                  onClicked: root.pendingSecurityDevice = null
                }
              }

              PanelSeparator {
                visible: index < (parent.advancedEntry
                  ? root.advancedDevices.length : root.typingDevices.length) - 1
                foreground: root.contentForeground
              }
            }
          }

          Repeater {
            model: root.typingDevices
            delegate: deviceEditorDelegate
          }

          Button {
            id: advancedDevicesButton
            visible: root.advancedDevices.length > 0
            width: parent.width
            text: (root.advancedDevicesVisible ? "Hide" : "Show") + " advanced devices ("
              + root.advancedDevices.length + ")"
            iconText: root.advancedDevicesVisible ? "󰅃" : "󰅀"
            leftAlign: true
            bordered: true
            focusable: true
            foreground: root.contentForeground
            accent: root.contentAccent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.subtitle
            onClicked: root.advancedDevicesVisible = !root.advancedDevicesVisible
          }

          Repeater {
            model: root.advancedDevicesVisible ? root.advancedDevices : []
            delegate: deviceEditorDelegate
          }

          Text {
            visible: root.draftError !== ""
            width: parent.width
            text: root.draftError
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.service && String(root.service.lastError || "") !== ""
            width: parent.width
            text: root.service ? String(root.service.lastError || "") : ""
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            text: "Back to layouts"
            iconText: "󰁍"
            leftAlign: true
            bordered: true
            focusable: true
            foreground: root.contentForeground
            accent: root.contentAccent
            fontFamily: root.contentFontFamily
            onClicked: root.cancelSettings()
          }
        }
      }
    }
  }
}
