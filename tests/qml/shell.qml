import QtQuick
import Quickshell
import "." as Qwitch

ShellRoot {
  id: harness

  property int failures: 0
  property int assertions: 0

  function check(condition, message) {
    assertions += 1
    if (condition) return
    failures += 1
    console.error("QWITCH_QML_ASSERTION_FAILED: " + message)
  }

  Item {
    id: anchor
    width: 24
    height: 24
  }

  QtObject {
    id: mockBar
    property color barForeground: "#d8dee9"
    property string fontFamily: "monospace"
    property string position: "top"
    property int barSize: 36
    property bool vertical: false
    property color urgent: "#bf616a"
    property var shell: null
  }

  QtObject {
    id: mockHost
    property var persisted: null
    function persistSettings(candidate) {
      persisted = JSON.parse(JSON.stringify(candidate))
      return true
    }
  }

  QtObject {
    id: mockService
    property var layouts: [
      { layout: "us", variant: "", label: "English", flag: "🇺🇸" },
      { layout: "tr", variant: "", label: "Turkish", flag: "🇹🇷" }
    ]
    property var configuredLayouts: layouts
    property var catalog: layouts
    property var devices: []
    property int maximumLayouts: 16
    property int activeIndex: 0
    property bool mixedState: false
    property bool busy: false
    property bool canSwitch: true
    property string nativeShortcutLabel: "Alt + Shift"
    property string shortcutConflict: ""
    property string lastError: ""
    function refreshCatalog() {}
    function refreshDevices() {}
    function displayTextFor(entry, mode) {
      if (!entry) return ""
      if (mode === "flag") return entry.flag || entry.label
      if (mode === "text") return entry.label || entry.flag
      return entry.flag ? entry.flag + " " + entry.label : entry.label
    }
    function validateShortcut() { return "" }
    function switchTo() { return true }
  }

  Qwitch.Panel {
    id: subject
    anchorItem: anchor
    bar: mockBar
    hostWidget: mockHost
    service: mockService
    settings: ({
      layouts: mockService.layouts,
      displayMode: "both",
      osdEnabled: false,
      shortcut: null,
      applicationMode: "global",
      applicationLayouts: ({}),
      deviceOverrides: ({}),
      adoptedExistingConfig: true,
      nativeXkbOption: "grp:alt_shift_toggle"
    })
  }

  function runSynchronousChecks() {
    subject.prepareDraft()
    subject.settingsPage = true

    var fields = [subject._layoutCodeEditor, subject._variantEditor,
      subject._shortLabelEditor, subject._flagEditor]
    for (var index = 1; index < fields.length; index++)
      check(fields[index].height === fields[0].height, "layout editors must share one height")
    for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
      var field = fields[fieldIndex]
      check(field.contentHeight + field.topPadding + field.bottomPadding <= field.height,
        "layout editor text must not be clipped")
      check(field.hoverEnabled === true, "native TextField hover behavior must remain enabled")
    }

    check(subject._shortLabelEditor.activeFocusOnPress,
      "a layout editor must retain native pointer focus behavior")
    subject._shortLabelEditor.text = "EN"
    subject._shortLabelEditor.textEdited()
    check(subject.draft.layouts[0].label === "EN", "editing must update the draft")

    subject._displayModeSelector.changed("text")
    check(subject.draft.displayMode === "text", "button selection must update display mode")
    subject._applicationModeSelector.changed("remember")
    check(subject.draft.applicationMode === "remember",
      "application scope selection must update the draft")
    check(subject.displayedShortcut() === "Not assigned",
      "a Hyprland shortcut must not masquerade as a qwitch shortcut")
    check(subject.nativeShortcutSummary() === "Alt + Shift",
      "the detected Hyprland shortcut must remain visible separately")
  }

  Timer {
    id: finishTimer
    interval: 700
    repeat: false
    onTriggered: {
      harness.check(mockHost.persisted !== null, "valid edits must auto-save")
      if (mockHost.persisted)
        harness.check(mockHost.persisted.layouts[0].label === "EN", "auto-save must persist edits")

      subject._settingsViewport.contentY = Math.min(120,
        Math.max(0, subject._settingsViewport.contentHeight - subject._settingsViewport.height))
      subject.close()
      harness.check(subject._settingsViewport.contentY === 0, "closing must reset the viewport")

      if (harness.failures === 0)
        console.log("QWITCH_QML_TESTS_PASSED: " + harness.assertions + " assertions")
      else
        console.error("QWITCH_QML_TESTS_FAILED: " + harness.failures + " of "
          + harness.assertions + " assertions")
      Qt.quit()
    }
  }

  Component.onCompleted: {
    Qt.callLater(function() {
      harness.runSynchronousChecks()
      finishTimer.start()
    })
  }
}
