const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")

const projectRoot = path.join(__dirname, "..")
const servicePath = path.join(projectRoot, "Service.qml")
const service = fs.readFileSync(servicePath, "utf8")
const panel = fs.readFileSync(path.join(projectRoot, "Panel.qml"), "utf8")
const barWidget = fs.readFileSync(path.join(projectRoot, "BarWidget.qml"), "utf8")
const readme = fs.readFileSync(path.join(projectRoot, "README.md"), "utf8")
const runtimeHelper = fs.readFileSync(path.join(projectRoot, "qwitch-runtime"), "utf8")

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
  assert.equal((service.match(/root\.mutationSuperseded\(exitCode\)/g) || []).length, 4)
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
  assert.match(service, /_pendingRestoreMatches, restoreLeaseIndexes\)/)
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
  assert.match(service, /if \(_rebaseAfterReload\) \{/)
  assert.match(service, /if \(!_runtimeReady \|\| _rebaseAfterReload \|\| abandonProcess\.running\)/)
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

test("first run adopts existing Hyprland layouts and observes the native group toggle", () => {
  assert.match(service, /function maybeAdoptExistingConfig\(\)/)
  assert.match(service, /candidate\.layouts = importingLayouts \? clone\(layouts, \[\]\) : clone\(configuredLayouts, \[\]\)/)
  assert.match(service, /candidate\.adoptedExistingConfig = true/)
  assert.match(service, /Model\.firstGroupToggle\(_observedKbOptions\)/)
  assert.match(service, /Model\.parseHyprOptionString\(root\._nativeOptionOutput\)/)
  assert.match(service, /"input:kb_options"/)
  assert.match(service, /detectedGroupToggle: Model\.firstGroupToggle/)
  assert.match(service, /nativeShortcutLabel: Model\.nativeXkbShortcutLabel/)
  assert.match(service, /nativeOptionProcess\.running = true/)
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
  assert.match(panel, /model: root\.typingDevices/)
  assert.match(panel, /model: root\.advancedDevicesVisible \? root\.advancedDevices : \[\]/)
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

test("bar clicks cycle layouts and reserve the menu for right click", () => {
  assert.match(barWidget, /buttonCode === Qt\.RightButton\) root\.toggle\(\)/)
  assert.match(barWidget, /buttonCode === Qt\.LeftButton[\s\S]*root\.service\.cycleNext\(\)/)
  assert.doesNotMatch(barWidget, /Qt\.RightButton\) root\.openSettings\(\)/)
})

test("the layout menu always renders flag and text", () => {
  assert.match(panel, /text: root\.displayFor\(modelData, "both"\)/)
  assert.doesNotMatch(panel,
    /text: root\.displayFor\(modelData,\s*root\.settings \? root\.settings\.displayMode/)
})

test("every bar instance renders the singleton service's active layout", () => {
  assert.match(barWidget, /shell\.serviceFor\(root\.moduleName\)/)
  assert.match(barWidget, /root\.service\.activeLayout/)
  assert.match(barWidget, /root\.service\.mixedState === true/)
})

test("panel headers and mixed control rows use compact aligned geometry", () => {
  assert.doesNotMatch(panel, /PanelHero\s*\{/)
  assert.match(panel, /id: mainTitle[\s\S]*anchors\.right: settingsButton\.left/)
  assert.match(panel, /id: osdSwitch[\s\S]*trackHeight: Style\.space\(18\)/)
  assert.match(panel, /id: moveUpButton[\s\S]*anchors\.verticalCenter: parent\.verticalCenter/)
  assert.match(panel, /Grid\s*\{[\s\S]*readonly property real fieldWidth: \(width - columnSpacing\) \/ 2/)
  assert.equal((panel.match(/width: parent\.fieldWidth/g) || []).length, 4)
  assert.equal((panel.match(/height: root\.settingsFieldHeight/g) || []).length, 4)
  assert.match(panel, /TextMetrics\s*\{[\s\S]*text: "English 🇺🇸"/)
  assert.match(panel, /ButtonGroup\s*\{\s*id: displayModeGroup/)
  assert.doesNotMatch(panel, /hoverEnabled: false/)
})

test("typing keyboards appear before the advanced device controls", () => {
  const typingList = panel.indexOf("model: root.typingDevices")
  const advancedToggle = panel.indexOf("id: advancedDevicesButton")
  const advancedList = panel.indexOf("model: root.advancedDevicesVisible ? root.advancedDevices : []")
  assert.ok(typingList >= 0 && advancedToggle > typingList && advancedList > advancedToggle)
})

test("README documents plugin updates and stale-shell recovery", () => {
  assert.match(readme, /omarchy plugin update io\.github\.aloglu\.qwitch/)
  assert.match(readme, /omarchy restart shell/)
  assert.match(readme, /fast-forward/i)
})

test("settings reopen at the top and present the native shortcut read-only", () => {
  assert.match(panel, /text: "󰌌  SWITCHING SHORTCUT"/)
  assert.match(panel, /root\.service\.nativeShortcutLabel/)
  assert.match(panel, /root\.service\.nativeShortcutLabel/)
  assert.match(panel, /"Configured in ~\/\.config\/hypr\/input\.lua"/)
  assert.match(panel, /"Configure it in ~\/\.config\/hypr\/input\.lua"/)
  assert.doesNotMatch(panel, /Record|recordShortcut|capturingShortcut|chooseNativeShortcut|chooseRecordedShortcut/)
  assert.match(panel, /settingsScroll\.contentY = 0/)
  assert.match(panel, /text: "qwitch: Settings"/)
  assert.match(panel, /text: "qwitch: Layouts"/)
  assert.doesNotMatch(panel, /Changes save automatically/i)
  assert.doesNotMatch(panel, /Saved automatically/i)
  assert.doesNotMatch(panel, /saveStatus/)
})

test("shortcut handling is strictly observational", () => {
  assert.match(service, /"hyprctl", "-j", "getoption", "input:kb_options"/)
  assert.match(service, /Model\.parseHyprOptionString/)
  assert.match(service, /Model\.firstGroupToggle/)
  assert.doesNotMatch(service, /bindingProcess|bindsProcess|hyprctl", "binds|hl\.bind|handle:unbind/)
  assert.doesNotMatch(service, /hl\.config\(\{ input = \{ kb_options/)
  assert.doesNotMatch(runtimeHelper, /bindingOwned|kbOptions|kb_options|handle:unbind/)
  assert.doesNotMatch(barWidget, /shortcut|nativeXkbOption/)
  assert.match(readme, /does not edit `~\/\.config\/hypr`/)
})

test("OSD is an all-or-nothing view of authoritative layout changes", () => {
  assert.match(service, /osdEnabled = next\.osdEnabled === true[\s\S]*if \(busy\)/)
  assert.match(service, /shell\.summon\("omarchy\.osd", JSON\.stringify\(payload\)\)/)
  assert.match(service, /onActiveIndexChanged:[\s\S]*root\.showLayoutOsd\(index\)/)
  assert.match(service, /function showLayoutOsd\(index\)/)
  assert.match(service, /if \(!osdEnabled \|\| !shell \|\| !Number\.isInteger\(target\)/)
  assert.doesNotMatch(service, /_showOsdAfterSwitch|_showOsdAfterExternalRefresh|internalLayoutEvent/)
  assert.match(panel, /Show all layout changes on OSD/)
  assert.match(readme, /OSD preference is all-or-nothing/)
})

test("per-application memory remains available through the native app identity", () => {
  assert.match(service, /target: ToplevelManager/)
  assert.match(service, /function onActiveToplevelChanged\(\) \{ root\.refreshActiveApplication\(\) \}/)
  assert.match(service, /target: ToplevelManager\.activeToplevel/)
  assert.match(service, /Model\.normalizeApplicationId\(toplevel\.appId \|\| ""\)/)
  assert.match(service, /scope === "application" \? settings\.applicationLayouts : windowLayouts/)
  assert.match(service, /Model\.rememberedLayoutIndex\(memories, identity, layouts\)/)
  assert.match(service, /switchTo\(target, false\)/)
  assert.match(service, /root\.rememberFocusedLayout\(root\._switchTarget,/)
  assert.match(service, /var learnedExternalLayout = mayLearnExternalLayout/)
  assert.match(service, /root\.rememberFocusedLayout\(root\.activeIndex,/)
  assert.match(panel, /value: String\(root\.draft\.layoutScope \|\| "global"\)/)
  assert.match(panel, /value: "global", label: "Global"/)
  assert.match(panel, /value: "application", label: "Per app"/)
})

test("per-window memory uses live Hyprland identities and remains session-only", () => {
  const manifest = fs.readFileSync(path.join(projectRoot, "manifest.json"), "utf8")
  assert.match(service, /activeWindowId = windowIdFor\(Hyprland\.activeToplevel\)/)
  assert.match(service, /return Model\.normalizeWindowAddress\(value\)/)
  assert.match(service, /target: Hyprland\.toplevels/)
  assert.match(service, /function onValuesChanged\(\) \{[\s\S]*root\.pruneWindowLayouts\(\)/)
  assert.match(service, /property var windowLayouts: \(\{\}\)/)
  assert.match(service, /if \(target < 0\) \{[\s\S]*rememberFocusedLayout\(activeIndex/)
  assert.match(service, /_layoutEventWindowId = root\.activeWindowId/)
  assert.match(service, /rememberFocusedLayout\(root\.activeIndex, learnedApplicationId, learnedWindowId\)/)
  assert.match(panel, /value: "window", label: "Per window"/)
  assert.doesNotMatch(manifest, /"windowLayouts"/)
})

test("app and window scopes follow global keyboard focus across monitors", () => {
  assert.match(service, /windowIdFor\(Hyprland\.activeToplevel\)/)
  assert.match(service, /applicationIdFor\(ToplevelManager\.activeToplevel\)/)
  assert.doesNotMatch(service, /activeMonitor.*(?:applicationLayouts|windowLayouts)/)
  assert.match(barWidget, /shell\.serviceFor\(root\.moduleName\)/)
  assert.match(readme, /single keyboard-focused\s+window regardless of which monitor/i)
})

test("native QML interaction harness covers the real settings panel", () => {
  const harness = fs.readFileSync(path.join(projectRoot, "tests/qml/shell.qml"), "utf8")
  const runner = fs.readFileSync(path.join(projectRoot, "tests/run-qml-tests.sh"), "utf8")
  assert.match(harness, /Panel\s*\{[\s\S]*id: subject/)
  assert.match(harness, /layout editor text must not be clipped/)
  assert.match(harness, /valid edits must auto-save/)
  assert.match(harness, /closing must reset the viewport/)
  assert.match(runner, /quickshell --path/)
})
