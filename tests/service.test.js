const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")

const projectRoot = path.join(__dirname, "..")
const servicePath = path.join(projectRoot, "Service.qml")
const service = fs.readFileSync(servicePath, "utf8")
const panel = fs.readFileSync(path.join(projectRoot, "Panel.qml"), "utf8")
const barWidget = fs.readFileSync(path.join(projectRoot, "BarWidget.qml"), "utf8")

test("project branding consistently uses lowercase qwitch", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(projectRoot, "manifest.json"), "utf8"))
  assert.equal(manifest.name, "qwitch")
  assert.equal(manifest.barWidget.displayName, "qwitch")

  for (const filename of [
    "BarWidget.qml", "Model.js", "Panel.qml", "README.md", "Service.qml",
    "manifest.json", "qwitch-runtime", "tests/model.test.js",
    "tests/runtime.test.js", "tests/service.test.js"
  ]) {
    const contents = fs.readFileSync(path.join(projectRoot, filename), "utf8")
    for (const match of contents.matchAll(/qwitch[A-Za-z0-9_]*/gi))
      assert.equal(match[0], match[0].toLowerCase(),
        `${filename} contains a non-lowercase qwitch identifier`)
  }
})

test("runtime mutations use the resident pre/post lease contract", () => {
  assert.match(service, /_residentRuntimeHelper/)
  assert.match(service, /function leasedCommand\(/)
  assert.match(service, /"mutate"/)
  assert.match(service, /JSON\.stringify\(preState\)/)
  assert.match(service, /JSON\.stringify\(postState\)/)
  assert.doesNotMatch(service, /\[_runtimeHelper,\s*"eval/)
})

test("mutation ownership failures always quiesce the old service", () => {
  assert.match(service, /function mutationSuperseded\(exitCode\)/)
  assert.match(service, /exitCode === 75 \|\| exitCode === 76/)
  assert.equal((service.match(/root\.mutationSuperseded\(exitCode\)/g) || []).length, 5)
})

test("layout mutations stay within the cleanup lease index schema", () => {
  assert.match(service, /readonly property int _maximumRuntimeLayouts: 16/)
  assert.match(service, /readonly property int maximumLayouts: _maximumRuntimeLayouts/)
  assert.match(service, /configuredLayouts\.length > _maximumRuntimeLayouts/)
  assert.match(service, /function safeRuntimeIndex\(value\)/)
  assert.match(service, /if \(!safeRuntimeIndex\(index\)\) continue/)
})

test("restore pre-state covers indexes produced before its batch completes", () => {
  assert.match(service, /var restoreLeaseIndexes = \(\{\}\)/)
  assert.match(service, /restoreLeaseIndexes\[fingerprint\] = \[\s*0,\s*baseline \? baseline\.index[\s\S]*current \? current\.active_layout_index/)
  assert.match(service, /_pendingRestoreMatches, restoreLeaseIndexes, _mayOwnShortcut/)
})

test("binding ownership survives a failed exact unbind", () => {
  assert.match(service, /old\.token ~= " \+ token/)
  assert.match(service, /return old_handle:unbind\(\)/)
  assert.match(service, /rawget\(_G, '__qwitch_owned_binding'\) == old then _G\.__qwitch_owned_binding = nil/)
  assert.match(service, /return handle:unbind\(\)/)
  assert.equal((service.match(/qwitch_unbind_failed/g) || []).length, 2)
})

test("service drains and freshly observes before runtime readiness", () => {
  assert.match(service, /function beginDrain\(/)
  assert.match(service, /_runtimeAwaitingFreshDevices = true/)
  assert.match(service, /_runtimeReadyAfterSerial = root\._deviceRefreshSerial/)
  assert.match(service, /_activeDeviceRefreshSerial > _runtimeReadyAfterSerial/)
  assert.match(service, /_runtimeReady = true/)
})

test("Hyprland reload abandons the exact old lease before rebasing", () => {
  assert.match(service, /function beginReloadAbandon\(\)/)
  assert.match(service, /_residentRuntimeHelper, "abandon", _leaseId/)
  assert.match(service, /_reloadAbandonEpoch = _runtimeEpoch/)
  assert.match(service, /_runtimeReadyAfterSerial = root\._deviceRefreshSerial/)
  assert.match(service, /_postReloadBindSerial = root\._bindRefreshSerial/)
  assert.match(service, /if \(_rebaseAfterReload \|\| abandonProcess\.running\)/)
  assert.match(service, /if \(!_runtimeReady \|\| _rebaseAfterReload \|\| abandonProcess\.running\s*\|\| bindingProcess\.running\)/)
})

test("service lease has heartbeat and kernel identity", () => {
  assert.match(service, /interval: 2000/)
  assert.match(service, /"heartbeat"/)
  assert.match(service, /inputName: String\(input\.name/)
  assert.match(service, /identity: deviceIdentity\(device\)/)
  assert.match(service, /ownedLayouts:/)
  assert.match(service, /ownedIndexes:/)
})

test("destruction retires the exact resident lease", () => {
  assert.match(service, /Component\.onDestruction: retireLease\(\)/)
  assert.match(service, /_residentRuntimeHelper, "retire", _leaseId/)
  assert.doesNotMatch(service, /pluginRegistry/)
  assert.doesNotMatch(service, /cleanupDetached/)
  assert.doesNotMatch(service, /detachedRuntimeCommand/)
})

test("first run adopts existing Hyprland layouts and the native group toggle", () => {
  assert.match(service, /function maybeAdoptExistingConfig\(\)/)
  assert.match(service, /candidate\.layouts = importingLayouts \? clone\(layouts, \[\]\) : clone\(configuredLayouts, \[\]\)/)
  assert.match(service, /candidate\.adoptedExistingConfig = true/)
  assert.match(service, /Model\.firstGroupToggle\(Model\.parseHyprOptionString/)
  assert.match(service, /"input:kb_options"/)
  assert.match(service, /shell\.updateEntryInline\("io\.github\.aloglu\.qwitch", candidate\)/)
})

test("running qwitch removes Omarchy's duplicate layout indicator natively", () => {
  assert.match(service, /function integrateWithOmarchyBar\(\)/)
  assert.match(service, /shell\.mutateShellConfig/)
  assert.match(service, /omarchy\.keyboard-layout/)
})

test("settings focus and manual XKB edits fail safely", () => {
  assert.match(panel, /focusTarget: root\.settingsPage \? settingsScroll : keyCatcher/)
  assert.match(panel, /settingsScroll\.forceActiveFocus\(\)/)
  assert.match(panel, /Model\.normalizeLayoutEntry\(entry\)/)
  assert.match(panel, /not available on this system/)
})

test("settings auto-save and layout selection adds immediately", () => {
  assert.match(panel, /id: autoSaveTimer/)
  assert.match(panel, /onTriggered: root\.saveSettings\(\)/)
  assert.match(panel, /root\.addSelectedCatalogLayout\(\)/)
  assert.doesNotMatch(panel, /text: .*"Save"/)
  assert.match(panel, /model: root\.visibleDevices/)
})

test("device override draft can visibly return a saved override to automatic", () => {
  assert.match(panel, /var explicitValue = String\(overrides\[fingerprint\] \|\| "auto"\)/)
  assert.doesNotMatch(panel, /overrides\[fingerprint\] \|\| \(device && device\.override\)/)
  assert.match(panel, /if \(value === "manage" \|\| value === "ignore"\) overrides\[fingerprint\] = value/)
})

test("bar settings synchronization cannot outlive its widget", () => {
  assert.match(barWidget, /id: settingsSyncTimer/)
  assert.match(barWidget, /Component\.onDestruction:[\s\S]*settingsSyncTimer\.stop\(\)/)
  assert.doesNotMatch(barWidget, /Qt\.callLater/)
})
