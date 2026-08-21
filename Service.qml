import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  property var settings: Model.defaultSettings()
  property var configuredLayouts: []
  property var layouts: []
  property var catalog: []
  property bool catalogLoading: false
  property string catalogError: ""

  property var devices: []
  readonly property var managedDevices: devices.filter(function(device) { return device.managed === true })
  readonly property var typingDevices: devices.filter(function(device) { return device.category === "keyboard" })
  readonly property string nativeShortcutLabel: Model.nativeXkbShortcutLabel(settings.nativeXkbOption)
  property int activeIndex: -1
  property bool mixedState: false
  readonly property var activeLayout: activeIndex >= 0 && activeIndex < layouts.length ? layouts[activeIndex] : null
  readonly property string displayText: mixedState ? "MIX" : displayTextFor(activeLayout, settings.displayMode)
  readonly property int _maximumRuntimeLayouts: 16
  readonly property int maximumLayouts: _maximumRuntimeLayouts

  readonly property bool busy: layoutProcess.running || switchProcess.running
    || rollbackProcess.running || bindingProcess.running || procInputProcess.running
    || devicesProcess.running || bootstrapProcess.running || drainProcess.running
    || abandonProcess.running
    || !_runtimeReady || _layoutPipeline || _rebaseAfterReload
  property string lastError: ""
  property string shortcutConflict: ""
  property string activeApplicationId: ""
  // Presentation preferences are safe to accept while the runtime service is
  // still draining its previous lease. Keeping them outside the mutation
  // queue makes the persisted OSD choice effective immediately after boot.
  property bool osdEnabled: false
  property string osdDisplayMode: "both"
  readonly property bool canSwitch: configuredLayouts.length > 0
    && configuredLayouts.length <= _maximumRuntimeLayouts
    && managedDevices.length > 0 && !busy

  property string _settingsSignature: ""
  property string _catalogOutput: ""
  property string _procInputOutput: ""
  property string _devicesOutput: ""
  property string _bindsOutput: ""
  property string _nativeOptionOutput: ""
  property bool _nativeOptionReady: false
  property bool _settingsReceived: false
  property bool _adoptionAttempted: false
  property var _knownBinds: []
  property bool _bindSnapshotReady: false
  property string _actionError: ""
  property bool _refreshPending: false
  property bool _bindRefreshPending: false
  property var _procDevices: []
  property var _baselines: ({})
  property var _lastApplied: ({})
  property double _ownerGeneration: Date.now() * 1000 + Math.floor(Math.random() * 1000)
  property string _ownerToken: "qwitch-" + _ownerGeneration
  property string _leaseId: "lease-" + _ownerGeneration + "-" + Math.floor(Math.random() * 1000000)
  readonly property string _bundledRuntimeHelper: decodeURIComponent(String(Qt.resolvedUrl("qwitch-runtime")).replace(/^file:\/\//, ""))
  readonly property string _residentRuntimeHelper: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
    + "/qwitch/qwitch-runtime-v1"
  property bool _runtimeReady: false
  property bool _runtimeAwaitingFreshDevices: false
  property int _runtimeReadyAfterSerial: -1
  property string _runtimeOutput: ""
  property bool _leaseMayExist: false
  property var _queuedSettings: null
  property bool _layoutPipeline: false
  property bool _reconcilePending: false
  property bool _rebaseAfterReload: false
  property int _deviceRefreshSerial: 0
  property int _activeDeviceRefreshSerial: 0
  property int _rebaseAfterSerial: -1
  property var _activeShortcut: null
  property var _pendingShortcut: null
  property var _pendingApplied: ({})
  property var _pendingRestoreMatches: ({})
  property bool _restoreAfterRefresh: false
  property bool _restorePolicyAfterRefresh: false
  property string _restoreReason: ""
  property int _switchAfterRefresh: -1
  property string _layoutOperation: ""
  property int _targetAfterApply: 0
  property bool _showOsdAfterSwitch: false
  property bool _rememberApplicationAfterSwitch: false
  property string _switchApplicationId: ""
  property bool _showOsdAfterExternalRefresh: false
  property int _externalRefreshPreviousIndex: -1
  property bool _externalRefreshPreviousMixed: false
  property int _switchTarget: -1
  property var _switchPrevious: ({})
  property string _bindingOperation: ""
  property string _pendingBindingError: ""
  property var _restoreKeepBaselines: ({})
  property var _restoreKeepApplied: ({})
  property var _restoreKeepMatches: ({})
  property bool _restoreRetrying: false
  property bool _postRestoreRefresh: false
  property bool _superseded: false
  property bool _mayOwnShortcut: false
  property int _runtimeEpoch: 0
  property int _bindingEpoch: 0
  property int _bindRefreshSerial: 0
  property int _activeBindRefreshSerial: 0
  property int _postReloadBindSerial: -1
  property int _reloadAbandonEpoch: -1
  property var _switchLeasePre: null
  property var _switchLeasePost: null

  function clone(value, fallback) {
    try { return JSON.parse(JSON.stringify(value)) } catch (error) { return fallback }
  }

  function applicationIdFor(toplevel) {
    if (!toplevel) return ""
    return Model.normalizeApplicationId(toplevel.appId || "")
  }

  function refreshActiveApplication() {
    activeApplicationId = applicationIdFor(ToplevelManager.activeToplevel)
    if (settings.applicationMode === "remember" && activeApplicationId)
      applicationLayoutTimer.restart()
  }

  function rememberApplicationLayout(index, applicationId) {
    var application = Model.normalizeApplicationId(applicationId || activeApplicationId)
    if (settings.applicationMode !== "remember" || !application) return
    var target = Number(index)
    if (!Number.isInteger(target) || target < 0 || target >= layouts.length) return
    var remembered = clone(settings.applicationLayouts, {})
    var key = Model.layoutKey(layouts[target])
    if (!key || remembered[application] === key) return
    var applications = Object.keys(remembered)
    if (remembered[application] === undefined && applications.length >= 128)
      delete remembered[applications[0]]
    remembered[application] = key
    var candidate = clone(settings, Model.defaultSettings())
    candidate.applicationLayouts = remembered
    candidate = Model.sanitizeSettings(candidate)
    applySettings(candidate, true)
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline("io.github.aloglu.qwitch", candidate)
  }

  function applyRememberedApplicationLayout() {
    if (settings.applicationMode !== "remember" || !activeApplicationId) return
    if (busy) {
      applicationLayoutTimer.restart()
      return
    }
    var target = Model.applicationLayoutIndex(settings.applicationLayouts,
      activeApplicationId, layouts)
    if (target < 0 || target === activeIndex) return
    switchTo(target, false, false)
  }

  function resetOwnerIdentity(minimumGeneration) {
    var minimum = Number(minimumGeneration || 0)
    var candidate = Date.now() * 1000 + Math.floor(Math.random() * 1000)
    _ownerGeneration = Math.max(candidate, minimum)
    _ownerToken = "qwitch-" + Math.floor(_ownerGeneration) + "-" + Math.floor(Math.random() * 1000000)
    _leaseId = "lease-" + Math.floor(_ownerGeneration) + "-" + Math.floor(Math.random() * 1000000)
  }

  function beginDrain() {
    if (_superseded || bootstrapProcess.running || drainProcess.running) return
    _runtimeOutput = ""
    drainProcess.command = [_residentRuntimeHelper, "drain", _leaseId,
      _ownerToken, String(Math.floor(_ownerGeneration))]
    drainProcess.running = true
  }

  function beginReloadAbandon() {
    if (_superseded || !_rebaseAfterReload || abandonProcess.running
        || bootstrapProcess.running || drainProcess.running
        || layoutProcess.running || switchProcess.running || rollbackProcess.running
        || bindingProcess.running) return
    _reloadAbandonEpoch = _runtimeEpoch
    abandonProcess.command = [_residentRuntimeHelper, "abandon", _leaseId,
      _ownerToken, String(Math.floor(_ownerGeneration)),
      String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")]
    abandonProcess.running = true
  }

  function deviceIdentity(device) {
    var source = device && device.identity ? device.identity : ({})
    return {
      inputName: String(source.inputName || ""),
      bus: String(source.bus || ""),
      vendor: String(source.vendor || ""),
      product: String(source.product || ""),
      uniq: String(source.uniq || ""),
      phys: String(source.phys || "")
    }
  }

  function uniqueLayoutPairs(values) {
    var seen = ({})
    var out = []
    var source = Array.isArray(values) ? values : []
    for (var i = 0; i < source.length; i++) {
      var layout = String(source[i] && source[i].layout || "")
      var variant = String(source[i] && source[i].variant || "")
      var key = layout + "\n" + variant
      if (!layout || seen[key]) continue
      seen[key] = true
      out.push({ layout: layout, variant: variant })
    }
    return out
  }

  function uniqueIndexes(values) {
    var seen = ({})
    var out = []
    var source = Array.isArray(values) ? values : []
    for (var i = 0; i < source.length; i++) {
      var index = Number(source[i])
      if (!safeRuntimeIndex(index) || seen[index]) continue
      seen[index] = true
      out.push(index)
    }
    return out
  }

  function leaseState(phase, baselinesValue, appliedValue, matchesValue,
                      extraIndexes, bindingOwned, status) {
    var baselineMap = baselinesValue || ({})
    var appliedMap = appliedValue || ({})
    var matchMap = matchesValue || ({})
    var extras = extraIndexes || ({})
    var records = []
    for (var fingerprint in baselineMap) {
      var baseline = baselineMap[fingerprint]
      var applied = appliedMap[fingerprint]
      if (!baseline || !applied || !safeDeviceName(applied.name || baseline.name)) continue
      var current = devices.find(function(device) { return device.fingerprint === fingerprint })
      var identity = baseline.identity || (current ? current.identity : null)
      if (!identity) continue
      var pairs = uniqueLayoutPairs(matchMap[fingerprint])
      if (pairs.length === 0)
        pairs = uniqueLayoutPairs([{ layout: applied.layout, variant: applied.variant }])
      var moreIndexes = extras[fingerprint] || extras[applied.name] || []
      var indexes = uniqueIndexes([applied.index].concat(Array.isArray(moreIndexes) ? moreIndexes : [moreIndexes]))
      records.push({
        fingerprint: String(fingerprint),
        name: String(applied.name || baseline.name),
        identity: deviceIdentity({ identity: identity }),
        baseline: {
          layout: String(baseline.layout || ""),
          variant: String(baseline.variant || ""),
          index: Number(baseline.index || 0)
        },
        ownedLayouts: pairs,
        ownedIndexes: indexes
      })
    }
    return {
      schema: 1,
      leaseId: _leaseId,
      token: _ownerToken,
      generation: Math.floor(_ownerGeneration),
      hyprInstance: String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""),
      status: status || "active",
      phase: String(phase || "active"),
      heartbeat: 0,
      bindingOwned: bindingOwned === true,
      devices: records
    }
  }

  function currentLeaseState(phase, bindingOwned, extraIndexes) {
    return leaseState(phase, _baselines, _lastApplied, _pendingRestoreMatches,
      extraIndexes || ({}), bindingOwned === undefined ? _mayOwnShortcut : bindingOwned)
  }

  function leasedCommand(mode, luaCode, batch, postLuaCode, preState, postState) {
    _leaseMayExist = true
    return [_residentRuntimeHelper, "mutate", _leaseId, _ownerToken,
      String(Math.floor(_ownerGeneration)), JSON.stringify(preState),
      JSON.stringify(postState), String(mode || ""), String(luaCode || ""),
      String(batch || ""), String(postLuaCode || "")]
  }

  function appliedAtIndexes(indexByName) {
    var out = clone(_lastApplied, {})
    for (var fingerprint in out) {
      var name = out[fingerprint].name
      if (indexByName[name] !== undefined) out[fingerprint].index = Number(indexByName[name])
    }
    return out
  }

  function retireLease() {
    if (!_residentRuntimeHelper || (!_runtimeReady && !bootstrapProcess.running && !drainProcess.running)) return
    Quickshell.execDetached([_residentRuntimeHelper, "retire", _leaseId,
      _ownerToken, String(Math.floor(_ownerGeneration))])
  }

  function updateLeasePresence() {
    _leaseMayExist = Object.keys(_baselines).length > 0 || _mayOwnShortcut
  }

  function markSuperseded() {
    _superseded = true
    _layoutPipeline = false
    _reconcilePending = false
    _refreshPending = false
    _bindRefreshPending = false
    _restoreAfterRefresh = false
    _restorePolicyAfterRefresh = false
    _switchAfterRefresh = -1
    _rememberApplicationAfterSwitch = false
    _switchApplicationId = ""
    applicationLayoutTimer.stop()
    _queuedSettings = null
    _layoutOperation = ""
    _bindingOperation = ""
    _activeShortcut = null
    _leaseMayExist = false
  }

  function mutationSuperseded(exitCode) {
    // Runtime mutation ownership failures use 75. Accept the drain retry code
    // defensively as well so an older service can never retry compositor work
    // after a successor has taken the lease.
    return exitCode === 75 || exitCode === 76
  }

  function setSettings(value) {
    if (_superseded) return
    _settingsReceived = true
    var next = Model.sanitizeSettings(value)
    osdEnabled = next.osdEnabled === true
    osdDisplayMode = String(next.displayMode || "both")
    var signature = JSON.stringify(next)
    if (busy) {
      _queuedSettings = signature === _settingsSignature ? null : next
      return
    }
    if (signature !== _settingsSignature) applySettings(next)
    maybeAdoptExistingConfig()
  }

  // Use Omarchy's in-process shell config API to avoid showing two keyboard
  // indicators while qwitch is enabled. The mutation is idempotent.
  function integrateWithOmarchyBar() {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    var sections = ["left", "center", "right"]
    var found = false
    var config = shell.shellConfig
    if (config && config.bar && config.bar.layout) {
      for (var i = 0; i < sections.length; i++) {
        var entries = config.bar.layout[sections[i]]
        if (!Array.isArray(entries)) continue
        for (var j = 0; j < entries.length; j++) {
          var entry = entries[j]
          var id = typeof entry === "string" ? entry : String(entry && entry.id || "")
          if (id === "omarchy.keyboard-layout") found = true
        }
      }
    }
    if (!found) return
    shell.mutateShellConfig(function(next) {
      if (!next.bar || !next.bar.layout) return
      for (var s = 0; s < sections.length; s++) {
        var values = next.bar.layout[sections[s]]
        if (!Array.isArray(values)) continue
        next.bar.layout[sections[s]] = values.filter(function(entry) {
          var id = typeof entry === "string" ? entry : String(entry && entry.id || "")
          return id !== "omarchy.keyboard-layout"
        })
      }
    })
  }

  // A fresh qwitch entry adopts the coherent layout list already active in
  // Hyprland. The marker prevents an intentional later removal from being
  // mistaken for another first run.
  function maybeAdoptExistingConfig() {
    if (_adoptionAttempted || !_settingsReceived || !_nativeOptionReady) return
    var detectedShortcut = Model.firstGroupToggle(Model.parseHyprOptionString(_nativeOptionOutput))
    if (settings.adoptedExistingConfig === true) {
      _adoptionAttempted = true
      // Keep the informational native shortcut current even after the initial
      // layout adoption. This also migrates installs whose earlier saved entry
      // did not include the detected input:kb_options value.
      if (String(settings.nativeXkbOption || "") !== detectedShortcut) {
        var refreshed = clone(settings, Model.defaultSettings())
        refreshed.nativeXkbOption = detectedShortcut
        applySettings(Model.sanitizeSettings(refreshed), true)
        if (shell && typeof shell.updateEntryInline === "function")
          shell.updateEntryInline("io.github.aloglu.qwitch", refreshed)
        Qt.callLater(root.finishMutation)
      }
      return
    }
    var importingLayouts = configuredLayouts.length === 0
    if (importingLayouts && (layouts.length === 0 || managedDevices.length === 0)) return

    _adoptionAttempted = true
    var candidate = clone(settings, Model.defaultSettings())
    candidate.layouts = importingLayouts ? clone(layouts, []) : clone(configuredLayouts, [])
    candidate.adoptedExistingConfig = true
    candidate.nativeXkbOption = detectedShortcut
    applySettings(Model.sanitizeSettings(candidate), true)
    if (importingLayouts) _reconcilePending = true
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline("io.github.aloglu.qwitch", candidate)
    Qt.callLater(root.finishMutation)
  }

  function applySettings(next, deferRuntime) {
    var signature = JSON.stringify(next)

    var previousLayouts = JSON.stringify(configuredLayouts)
    var previousOverrides = JSON.stringify(settings && settings.deviceOverrides ? settings.deviceOverrides : {})
    var previousShortcut = JSON.stringify(settings && settings.shortcut ? settings.shortcut : null)
    var previousApplicationMode = String(settings && settings.applicationMode || "global")
    var previousApplicationLayouts = JSON.stringify(
      settings && settings.applicationLayouts ? settings.applicationLayouts : {})
    settings = next
    osdEnabled = next.osdEnabled === true
    osdDisplayMode = String(next.displayMode || "both")
    configuredLayouts = next.layouts
    _settingsSignature = signature
    recomputeLayouts()

    var overridesChanged = JSON.stringify(next.deviceOverrides || {}) !== previousOverrides
    var layoutsChanged = JSON.stringify(configuredLayouts) !== previousLayouts
    var shortcutChanged = JSON.stringify(next.shortcut || null) !== previousShortcut
    var applicationBehaviorChanged = String(next.applicationMode || "global") !== previousApplicationMode
      || JSON.stringify(next.applicationLayouts || {}) !== previousApplicationLayouts
    if (deferRuntime === true) {
      if (overridesChanged && Object.keys(_lastApplied).length > 0)
        _restorePolicyAfterRefresh = true
      if (shortcutChanged) _bindRefreshPending = true
      if (applicationBehaviorChanged) applicationLayoutTimer.restart()
      return
    }
    if (overridesChanged && Object.keys(_lastApplied).length > 0) {
      requestRestore("Device policy changed")
    } else if (layoutsChanged) {
      reconcileRuntimeLayouts()
    }
    if (shortcutChanged) refreshBinds()
    if (applicationBehaviorChanged) applicationLayoutTimer.restart()
  }

  function finishMutation() {
    Qt.callLater(function() {
      if (root._superseded) return
      if (!root._runtimeReady) return
      if (layoutProcess.running || switchProcess.running || rollbackProcess.running
          || bindingProcess.running || procInputProcess.running || devicesProcess.running)
        return
      if (root._rebaseAfterReload) return
      if (root._layoutPipeline) return
      if (root._queuedSettings) {
        var queued = root._queuedSettings
        root._queuedSettings = null
        root.setSettings(queued)
        Qt.callLater(root.finishMutation)
        return
      }
      if (root._reconcilePending) {
        root._reconcilePending = false
        root.reconcileRuntimeLayouts()
      }
      if (root._bindRefreshPending) root.refreshBinds()
    })
  }

  function validateShortcut(shortcut) {
    var syntaxError = Model.validateShortcut(shortcut)
    if (syntaxError || !shortcut) return syntaxError
    if (!_bindSnapshotReady) return "Still inspecting existing Hyprland shortcuts"
    var desired = Model.normalizeShortcut(shortcut)
    for (var i = 0; i < _knownBinds.length; i++) {
      var bind = _knownBinds[i]
      if (ownBinding(bind)) continue
      if (Model.shortcutsConflict(desired, bind))
        return "Already used by " + String(bind.description || bind.dispatcher || "another Hyprland action")
    }
    return ""
  }

  function displayTextFor(entry, mode) {
    if (!entry) return "—"
    return Model.displayForLayout(entry, mode || "both")
  }

  function refreshCatalog() {
    if (catalogProcess.running) return
    catalogLoading = true
    catalogError = ""
    _catalogOutput = ""
    catalogProcess.running = true
  }

  function refreshDevices(force) {
    if (_superseded) return
    if (force !== true && (layoutProcess.running || switchProcess.running
        || rollbackProcess.running || _layoutPipeline)) {
      _refreshPending = true
      return
    }
    if (procInputProcess.running || devicesProcess.running) {
      _refreshPending = true
      return
    }

    _refreshPending = false
    _deviceRefreshSerial += 1
    _activeDeviceRefreshSerial = _deviceRefreshSerial
    _procInputOutput = ""
    procInputProcess.running = true
  }

  function recomputeLayouts() {
    if (configuredLayouts.length > 0) {
      layouts = configuredLayouts
      recomputeActiveState()
      return
    }

    // Before first-run adoption completes, reflect one unambiguous existing
    // device without taking ownership of it.
    var candidates = managedDevices
    if (candidates.length === 0) {
      layouts = []
      activeIndex = -1
      mixedState = false
      return
    }

    var layoutSpec = String(candidates[0].layout || "")
    var variantSpec = String(candidates[0].variant || "")
    for (var i = 1; i < candidates.length; i++) {
      if (String(candidates[i].layout || "") !== layoutSpec || String(candidates[i].variant || "") !== variantSpec) {
        layouts = []
        activeIndex = -1
        mixedState = true
        return
      }
    }

    var names = layoutSpec ? layoutSpec.split(",") : []
    var variants = variantSpec.split(",")
    var observed = []
    for (var j = 0; j < names.length; j++) {
      var entry = Model.normalizeLayoutEntry({ layout: names[j], variant: variants[j] || "" }, catalog)
      if (entry) observed.push(entry)
    }
    layouts = observed
    recomputeActiveState()
  }

  function recomputeActiveState() {
    var candidates = managedDevices
    if (candidates.length === 0) {
      activeIndex = -1
      mixedState = false
      return
    }

    var first = Number(candidates[0].active_layout_index)
    if (!isFinite(first)) first = -1
    for (var i = 1; i < candidates.length; i++) {
      var current = Number(candidates[i].active_layout_index)
      if (!isFinite(current) || current !== first) {
        activeIndex = -1
        mixedState = true
        return
      }
    }

    activeIndex = first >= 0 && first < layouts.length ? first : -1
    mixedState = false
  }

  function consumeDeviceOutput() {
    var payload
    try {
      payload = JSON.parse(_devicesOutput || "{}")
    } catch (error) {
      _showOsdAfterExternalRefresh = false
      lastError = "Could not read Hyprland keyboards"
      finishDeviceRefresh()
      return
    }

    // A settings save that arrived during this read wins before the snapshot
    // can trigger any restore, switch, or apply decision.
    if (_queuedSettings) {
      var queued = _queuedSettings
      _queuedSettings = null
      _restoreAfterRefresh = false
      _restoreReason = ""
      _switchAfterRefresh = -1
      _postRestoreRefresh = false
      _layoutPipeline = false
      applySettings(queued, true)
    }

    var previouslyObservedIndex = activeIndex
    var previouslyObservedMixed = mixedState
    var mayLearnExternalLayout = _runtimeReady && !_layoutPipeline
      && !_rebaseAfterReload && !_superseded
    var keyboards = Array.isArray(payload.keyboards) ? payload.keyboards : []
    var overrides = settings && settings.deviceOverrides ? settings.deviceOverrides : {}
    var next = []
    for (var i = 0; i < keyboards.length; i++) {
      var keyboard = keyboards[i]
      var input = Model.matchInputDevice(keyboard.name, _procDevices)
      var fingerprint = Model.stableDeviceFingerprint(input, keyboard)
      var override = fingerprint && overrides ? overrides[fingerprint] : undefined
      var verdict = Model.classifyDevice(keyboard, input, override)
      next.push({
        name: String(keyboard.name || ""),
        label: input && input.name ? input.name : String(keyboard.name || "Unknown keyboard"),
        fingerprint: fingerprint,
        layout: String(keyboard.layout || ""),
        variant: String(keyboard.variant || ""),
        active_keymap: String(keyboard.active_keymap || ""),
        active_layout_index: Number(keyboard.active_layout_index || 0),
        managed: verdict.managed === true,
        security: verdict.security === true,
        ambiguous: verdict.ambiguous === true,
        requiresConfirmation: verdict.requiresConfirmation === true,
        category: String(verdict.category || ""),
        reason: String(verdict.reason || ""),
        source: String(verdict.source || "automatic"),
        override: override || "auto",
        identity: input ? {
          inputName: String(input.name || ""),
          bus: String(input.bus || ""),
          vendor: String(input.vendor || input.vendorId || ""),
          product: String(input.product || input.productId || ""),
          uniq: String(input.uniq || ""),
          phys: String(input.phys || "")
        } : null
      })
    }

    devices = next
    recomputeLayouts()
    var learnedExternalLayout = mayLearnExternalLayout
      && !mixedState && activeIndex >= 0
      && (previouslyObservedMixed || activeIndex !== previouslyObservedIndex)
    var showExternalOsd = _showOsdAfterExternalRefresh
      && !mixedState && activeIndex >= 0
      && (_externalRefreshPreviousMixed || activeIndex !== _externalRefreshPreviousIndex)
    _showOsdAfterExternalRefresh = false
    maybeAdoptExistingConfig()
    if (_runtimeAwaitingFreshDevices && _activeDeviceRefreshSerial > _runtimeReadyAfterSerial) {
      _runtimeAwaitingFreshDevices = false
      _runtimeReadyAfterSerial = -1
      _runtimeReady = true
      _reconcilePending = true
      _bindRefreshPending = true
    }
    finishDeviceRefresh()

    // Native XKB group toggles and other compositor-side changes do not enter
    // switchTo(). Learn any coherent externally observed change independently
    // of whether its Hyprland event also requested an OSD notification.
    if (learnedExternalLayout) root.rememberApplicationLayout(root.activeIndex)
    if (showExternalOsd) Qt.callLater(root.showLayoutOsd)

    if (_superseded) return

    if (_rebaseAfterReload && _activeDeviceRefreshSerial <= _rebaseAfterSerial) return

    if (_rebaseAfterReload) {
      beginReloadAbandon()
      return
    }

    if (_restorePolicyAfterRefresh) {
      _restorePolicyAfterRefresh = false
      _layoutPipeline = true
      Qt.callLater(function() { root.restoreOwnedLayouts("Device policy changed") })
      return
    }

    if (_restoreAfterRefresh) {
      _restoreAfterRefresh = false
      var restoreReason = _restoreReason
      _restoreReason = ""
      Qt.callLater(function() { root.restoreOwnedLayouts(restoreReason) })
      return
    }

    if (_switchAfterRefresh >= 0) {
      var switchTarget = _switchAfterRefresh
      _switchAfterRefresh = -1
      Qt.callLater(function() {
        if (!root.switchTo(switchTarget, false, false)) {
          root._layoutPipeline = false
          root._reconcilePending = true
          root.finishMutation()
        }
      })
      return
    }

    // Restore before an ignore override (or a more conservative automatic
    // verdict) stops a keyboard from being managed.
    for (var fingerprint in _lastApplied) {
      var ownedDevice = next.find(function(device) { return device.fingerprint === fingerprint })
      if (ownedDevice && !ownedDevice.managed) {
        _layoutPipeline = true
        Qt.callLater(function() { root.restoreOwnedLayouts("Device no longer managed") })
        return
      }
    }
    if (_postRestoreRefresh) {
      _postRestoreRefresh = false
      if (configuredLayouts.length === 0 && Object.keys(_lastApplied).length > 0) {
        finishMutation()
        return
      }
    }
    reconcileRuntimeLayouts()
    finishMutation()
  }

  function finishDeviceRefresh() {
    if (_refreshPending) Qt.callLater(refreshDevices)
  }

  function safeDeviceName(name) {
    return /^[A-Za-z0-9_.:+-]+$/.test(String(name || ""))
  }

  function safeRuntimeIndex(value) {
    var index = Number(value)
    return Number.isInteger(index) && index >= 0 && index < _maximumRuntimeLayouts
  }

  function runtimeLayoutLimitError() {
    return "qwitch supports at most " + _maximumRuntimeLayouts + " layouts"
  }

  function configuredLayoutSpec() {
    return configuredLayouts.map(function(entry) { return entry.layout }).join(",")
  }

  function configuredVariantSpec() {
    return configuredLayouts.map(function(entry) { return entry.variant || "" }).join(",")
  }

  function captureBaselines() {
    var next = clone(_baselines, {})
    for (var i = 0; i < managedDevices.length; i++) {
      var device = managedDevices[i]
      if (!device.fingerprint || next[device.fingerprint]) continue
      next[device.fingerprint] = {
        name: device.name,
        layout: device.layout,
        variant: device.variant,
        index: device.active_layout_index,
        identity: deviceIdentity(device)
      }
    }
    _baselines = next
  }

  function layoutSignature() {
    return configuredLayoutSpec() + "\n" + configuredVariantSpec()
  }

  function needsLayoutApply() {
    if (configuredLayouts.length === 0 || managedDevices.length === 0) return false
    var signature = layoutSignature()
    for (var i = 0; i < managedDevices.length; i++) {
      var device = managedDevices[i]
      var applied = _lastApplied[device.fingerprint]
      if (!applied || applied.signature !== signature || applied.name !== device.name) return true
      if (device.layout !== configuredLayoutSpec() || device.variant !== configuredVariantSpec()) return true
    }
    return false
  }

  function reconcileRuntimeLayouts() {
    if (_superseded) return
    if (_rebaseAfterReload) {
      _reconcilePending = true
      return
    }
    if (busy) {
      _reconcilePending = true
      return
    }

    if (configuredLayouts.length === 0) {
      if (Object.keys(_lastApplied).length > 0) requestRestore("Settings cleared")
      return
    }
    if (configuredLayouts.length > _maximumRuntimeLayouts) {
      lastError = runtimeLayoutLimitError()
      if (Object.keys(_lastApplied).length > 0)
        requestRestore("Configured layout limit exceeded")
      return
    }
    if (managedDevices.length === 0) return
    if (!needsLayoutApply()) return

    // A baseline outside the lease schema cannot be restored exactly. Refuse
    // the first write for that device instead of taking incomplete ownership.
    for (var baselineIndex = 0; baselineIndex < managedDevices.length; baselineIndex++) {
      var baselineDevice = managedDevices[baselineIndex]
      if (!_baselines[baselineDevice.fingerprint]
          && !safeRuntimeIndex(baselineDevice.active_layout_index)) {
        lastError = "A keyboard reported an unsupported active layout index"
        return
      }
    }

    captureBaselines()
    var layout = configuredLayoutSpec()
    var variant = configuredVariantSpec()
    var statements = []
    // Keep ownership records for unplugged devices so a later settings change
    // cannot orphan their name-specific runtime rule.
    var pending = clone(_lastApplied, {})
    var restoreMatches = clone(_pendingRestoreMatches, {})
    var signature = layoutSignature()
    _targetAfterApply = activeIndex >= 0 && activeIndex < configuredLayouts.length ? activeIndex : 0
    for (var i = 0; i < managedDevices.length; i++) {
      var device = managedDevices[i]
      if (!safeDeviceName(device.name)) continue
      statements.push("hl.device({ name = " + Model.luaQuote(device.name)
        + ", kb_layout = " + Model.luaQuote(layout)
        + ", kb_variant = " + Model.luaQuote(variant) + " })")
      pending[device.fingerprint] = {
        name: device.name,
        layout: layout,
        variant: variant,
        index: _targetAfterApply,
        signature: signature
      }
      var accepted = []
      var prior = _lastApplied[device.fingerprint]
      if (prior) accepted.push({ layout: prior.layout, variant: prior.variant })
      accepted.push({ layout: layout, variant: variant })
      restoreMatches[device.fingerprint] = accepted
    }
    if (statements.length === 0) return

    _pendingApplied = pending
    _pendingRestoreMatches = restoreMatches
    _layoutOperation = "apply"
    _restoreRetrying = false
    _layoutPipeline = true
    _actionError = ""
    var token = Model.luaQuote(_ownerToken)
    var generation = String(Math.floor(_ownerGeneration))
    var code = "do local generation = " + generation + "; local current = tonumber(rawget(_G, '__qwitch_generation') or 0); "
      + "local cancelled = tonumber(rawget(_G, '__qwitch_cancelled_generation') or 0); "
      + "if cancelled >= generation or generation < current then error('qwitch_stale') end; _G.__qwitch_generation = generation; "
      + "local owner = { token = " + token + ", phase = 'applying' }; "
      + "_G.__qwitch_layout_owner = owner; " + statements.join("; ")
      + "; owner.phase = 'active' end"
    var applyIndexes = ({})
    for (var j = 0; j < managedDevices.length; j++)
      applyIndexes[managedDevices[j].fingerprint] = [managedDevices[j].active_layout_index, _targetAfterApply, 0]
    var preLease = leaseState("layout-applying", _baselines, pending,
      restoreMatches, applyIndexes, _mayOwnShortcut)
    var postLease = leaseState("layout-active", _baselines, pending,
      restoreMatches, applyIndexes, _mayOwnShortcut)
    layoutProcess.command = leasedCommand("eval", code, "", "", preLease, postLease)
    layoutProcess.running = true
  }

  function requestRestore(reason) {
    if (_superseded) return
    if (!_runtimeReady || _rebaseAfterReload || abandonProcess.running) {
      _reconcilePending = true
      return
    }
    if (layoutProcess.running || switchProcess.running || rollbackProcess.running
        || bindingProcess.running) {
      _reconcilePending = true
      return
    }
    _layoutPipeline = true
    _restoreReason = String(reason || "Restore requested")
    _restoreAfterRefresh = true
    refreshDevices(true)
  }

  function matchesOwnedLayout(fingerprint, current) {
    var candidates = _pendingRestoreMatches[fingerprint]
    if (!Array.isArray(candidates) || candidates.length === 0) {
      var applied = _lastApplied[fingerprint]
      candidates = applied ? [{ layout: applied.layout, variant: applied.variant }] : []
    }
    for (var i = 0; i < candidates.length; i++) {
      if (current.layout === candidates[i].layout && current.variant === candidates[i].variant) return true
    }
    var baseline = _baselines[fingerprint]
    if (_restoreRetrying && baseline
        && current.layout === baseline.layout && current.variant === baseline.variant) return true
    return false
  }

  function sameNameHasDifferentFingerprint(name, fingerprint) {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].name === name && devices[i].fingerprint !== fingerprint) return true
    }
    return false
  }

  function ownedIndexMatches(applied, current) {
    var expected = Number(applied && applied.index)
    var actual = Number(current && current.active_layout_index)
    return Number.isInteger(expected) && Number.isInteger(actual) && expected === actual
  }

  function completeLayoutRestore() {
    _layoutOperation = ""
    _lastApplied = _restoreKeepApplied
    _baselines = _restoreKeepBaselines
    _pendingRestoreMatches = _restoreKeepMatches
    _pendingApplied = ({})
    _restoreKeepApplied = ({})
    _restoreKeepBaselines = ({})
    _restoreKeepMatches = ({})
    _restoreRetrying = false
    _layoutPipeline = false
    updateLeasePresence()
    if (Object.keys(_baselines).length === 0) lastError = ""
    _postRestoreRefresh = true
    refreshDevices()
  }

  function releaseLayoutOwnership() {
    _layoutOperation = "release"
    _actionError = ""
    var token = Model.luaQuote(_ownerToken)
    var generation = String(Math.floor(_ownerGeneration))
    var code = "do local current = tonumber(rawget(_G, '__qwitch_generation') or 0); "
      + "local owner = rawget(_G, '__qwitch_layout_owner'); "
      + "if current > " + generation + " or (owner and owner.token ~= " + token + ") then error('qwitch_stale') end; "
      + "if owner and owner.token == " + token + " then _G.__qwitch_layout_owner = nil end end"
    var preLease = currentLeaseState("layout-releasing", _mayOwnShortcut)
    var postLease = leaseState("layout-released", ({}), ({}), ({}), ({}), _mayOwnShortcut)
    layoutProcess.command = leasedCommand("eval", code, "", "", preLease, postLease)
    layoutProcess.running = true
  }

  function restoreOwnedLayouts(reason) {
    if (!_runtimeReady || _rebaseAfterReload || abandonProcess.running
        || bindingProcess.running) {
      _reconcilePending = true
      return
    }
    if (layoutProcess.running || switchProcess.running || rollbackProcess.running) {
      _reconcilePending = true
      return
    }
    var statements = []
    var restoreIndices = ({})
    var restore = _baselines
    var keepBaselines = ({})
    var keepApplied = ({})
    var keepMatches = ({})
    var restoreLeaseIndexes = ({})
    for (var fingerprint in restore) {
      var baseline = restore[fingerprint]
      var current = devices.find(function(device) { return device.fingerprint === fingerprint })
      var applied = _lastApplied[fingerprint] || _pendingApplied[fingerprint]
      restoreLeaseIndexes[fingerprint] = [
        0,
        baseline ? baseline.index : undefined,
        applied ? applied.index : undefined,
        current ? current.active_layout_index : undefined
      ]
      // Compare-and-restore: leave a device alone if somebody changed it after
      // qwitch's last successful write. If it is unplugged, restore the owned
      // name-specific rule so qwitch's layout does not return with the device.
      if (current && !matchesOwnedLayout(fingerprint, current)) continue
      if (!current && !applied) continue
      var deviceName = current ? current.name : (applied.name || baseline.name)
      if (!current && sameNameHasDifferentFingerprint(deviceName, fingerprint)) {
        keepBaselines[fingerprint] = baseline
        keepApplied[fingerprint] = applied
        if (_pendingRestoreMatches[fingerprint])
          keepMatches[fingerprint] = _pendingRestoreMatches[fingerprint]
        continue
      }
      if (!safeDeviceName(deviceName)) continue
      statements.push("hl.device({ name = " + Model.luaQuote(deviceName)
        + ", kb_layout = " + Model.luaQuote(baseline.layout)
        + ", kb_variant = " + Model.luaQuote(baseline.variant) + " })")
      if (current && ownedIndexMatches(applied, current)) restoreIndices[deviceName] = baseline.index
    }

    _restoreKeepBaselines = keepBaselines
    _restoreKeepApplied = keepApplied
    _restoreKeepMatches = keepMatches
    if (Object.keys(keepBaselines).length > 0)
      lastError = "Waiting to safely restore a keyboard whose device name was reused"

    if (statements.length === 0) {
      _layoutPipeline = false
      if (Object.keys(keepBaselines).length > 0) {
        completeLayoutRestore()
      } else {
        _layoutPipeline = true
        releaseLayoutOwnership()
      }
      return
    }

    _layoutOperation = "restore"
    _actionError = ""
    var token = Model.luaQuote(_ownerToken)
    var generation = String(Math.floor(_ownerGeneration))
    var code = "do local owner = rawget(_G, '__qwitch_layout_owner'); "
      + "local current = tonumber(rawget(_G, '__qwitch_generation') or 0); "
      + "if current > " + generation + " or not owner or owner.token ~= " + token + " then error('qwitch_stale') end; "
      + "owner.phase = 'restoring'; " + statements.join("; ")
      + " end"
    var postCode = Object.keys(keepBaselines).length > 0
      ? "do local owner = rawget(_G, '__qwitch_layout_owner'); if owner and owner.token == "
        + token + " then owner.phase = 'active' end end"
      : "do local owner = rawget(_G, '__qwitch_layout_owner'); if owner and owner.token == "
        + token + " then _G.__qwitch_layout_owner = nil end end"
    var preLease = leaseState("layout-restoring", _baselines,
      Object.keys(_lastApplied).length > 0 ? _lastApplied : _pendingApplied,
      _pendingRestoreMatches, restoreLeaseIndexes, _mayOwnShortcut)
    var postLease = leaseState("layout-restore-result", keepBaselines,
      keepApplied, keepMatches, ({}), _mayOwnShortcut)
    layoutProcess.command = leasedCommand("eval-batch-eval", code,
      switchBatch(restoreIndices), postCode, preLease, postLease)
    layoutProcess.running = true
  }

  function switchBatch(indexByName) {
    var parts = []
    for (var name in indexByName) {
      if (!safeDeviceName(name)) continue
      var index = Number(indexByName[name])
      if (!safeRuntimeIndex(index)) continue
      parts.push("switchxkblayout " + name + " " + index)
    }
    return parts.join(" ; ")
  }

  function ownershipGuardCode() {
    var token = Model.luaQuote(_ownerToken)
    var generation = String(Math.floor(_ownerGeneration))
    return "do local current = tonumber(rawget(_G, '__qwitch_generation') or 0); "
      + "local cancelled = tonumber(rawget(_G, '__qwitch_cancelled_generation') or 0); "
      + "local owner = rawget(_G, '__qwitch_layout_owner'); "
      + "if cancelled >= " + generation + " or current > " + generation
      + " or not owner or owner.token ~= " + token + " then error('qwitch_stale') end end"
  }

  function switchTo(index, showOsd, rememberApplication) {
    if (_superseded) {
      lastError = "A newer qwitch service owns the runtime state"
      return false
    }
    if (!_runtimeReady) {
      lastError = "qwitch is restoring runtime state from an earlier service"
      return false
    }
    if (configuredLayouts.length > _maximumRuntimeLayouts) {
      lastError = runtimeLayoutLimitError()
      return false
    }
    var target = Number(index)
    if (!Number.isInteger(target) || target < 0 || target >= layouts.length) {
      lastError = "Choose a valid keyboard layout"
      return false
    }
    if (configuredLayouts.length === 0) {
      lastError = "Add at least one layout before switching"
      return false
    }
    if (_rebaseAfterReload) {
      lastError = "qwitch is refreshing after a Hyprland reload"
      return false
    }
    if (managedDevices.length === 0) {
      lastError = "No safe typing keyboard is available"
      return false
    }
    if (needsLayoutApply()) {
      lastError = "qwitch is synchronizing keyboard layouts"
      reconcileRuntimeLayouts()
      return false
    }
    if (switchProcess.running || layoutProcess.running || rollbackProcess.running
        || bindingProcess.running || procInputProcess.running || devicesProcess.running) {
      lastError = "A keyboard change is already in progress"
      return false
    }

    var targets = {}
    var previous = {}
    for (var i = 0; i < managedDevices.length; i++) {
      var device = managedDevices[i]
      if (!safeDeviceName(device.name)) continue
      targets[device.name] = target
      previous[device.name] = device.active_layout_index
    }
    var batch = switchBatch(targets)
    if (!batch) {
      lastError = "No safe keyboard target was found"
      return false
    }

    _switchTarget = target
    _switchPrevious = previous
    _showOsdAfterSwitch = showOsd !== false
    _rememberApplicationAfterSwitch = rememberApplication !== false
    _switchApplicationId = _rememberApplicationAfterSwitch ? activeApplicationId : ""
    _layoutPipeline = true
    _actionError = ""
    var leaseIndexes = ({})
    for (var fingerprint in _lastApplied) {
      var ownedName = _lastApplied[fingerprint].name
      leaseIndexes[fingerprint] = [previous[ownedName], target]
    }
    var targetApplied = appliedAtIndexes(targets)
    _switchLeasePre = leaseState("layout-switching", _baselines, targetApplied,
      ({}), leaseIndexes, _mayOwnShortcut)
    _switchLeasePost = leaseState("layout-active", _baselines, targetApplied,
      ({}), ({}), _mayOwnShortcut)
    switchProcess.command = leasedCommand("eval-then-batch", ownershipGuardCode(),
      batch, "", _switchLeasePre, _switchLeasePost)
    switchProcess.running = true
    return true
  }

  function cycleNext() {
    if (layouts.length < 2) {
      lastError = layouts.length === 0 ? "Set up at least one layout" : "Only one layout is configured"
      return false
    }
    var next = mixedState || activeIndex < 0 ? 0 : (activeIndex + 1) % layouts.length
    return switchTo(next, true)
  }

  function updateDevicesAfterSwitch(index) {
    var next = []
    for (var i = 0; i < devices.length; i++) {
      var source = devices[i]
      var copy = clone(source, {})
      if (copy.managed) {
        copy.layout = configuredLayoutSpec()
        copy.variant = configuredVariantSpec()
        copy.active_layout_index = index
      }
      next.push(copy)
    }
    devices = next
    activeIndex = index
    mixedState = false

    var applied = clone(_lastApplied, {})
    var signature = layoutSignature()
    for (var j = 0; j < managedDevices.length; j++) {
      var device = managedDevices[j]
      applied[device.fingerprint] = {
        name: device.name,
        layout: configuredLayoutSpec(),
        variant: configuredVariantSpec(),
        index: index,
        signature: signature
      }
    }
    _lastApplied = applied
  }

  function showLayoutOsd() {
    if (!osdEnabled || !shell || !activeLayout) return
    var mode = osdDisplayMode || "both"
    var label = activeLayout.label || String(activeLayout.layout || "").toUpperCase()
    var flag = activeLayout.flag || ""
    var payload
    if (mode === "flag" && flag) payload = { icon: flag, message: "" }
    else if (mode === "text") payload = { icon: "keyboard", message: label }
    else if (flag) payload = { icon: flag, message: label }
    else payload = { icon: "keyboard", message: label }
    shell.summon("omarchy.osd", JSON.stringify(payload))
  }

  function refreshBinds() {
    if (_superseded) return
    if (!_runtimeReady || _rebaseAfterReload || abandonProcess.running) {
      _bindRefreshPending = true
      return
    }
    if (_layoutPipeline || layoutProcess.running || switchProcess.running || rollbackProcess.running) {
      _bindRefreshPending = true
      return
    }
    if (bindsProcess.running || bindingProcess.running) {
      _bindRefreshPending = true
      return
    }
    _bindRefreshPending = false
    _bindsOutput = ""
    _bindRefreshSerial += 1
    _activeBindRefreshSerial = _bindRefreshSerial
    bindsProcess.running = true
  }

  function ownBinding(bind) {
    var description = String(bind && bind.description ? bind.description : "")
    var arg = String(bind && bind.arg ? bind.arg : "")
    return description.toLowerCase() === "qwitch: next layout"
      && arg.indexOf("omarchy-shell -q qwitch nextLayout") !== -1
  }

  function consumeBinds() {
    if (_superseded) return
    if (_rebaseAfterReload || abandonProcess.running) {
      _bindRefreshPending = true
      return
    }
    if (_postReloadBindSerial >= 0 && _activeBindRefreshSerial <= _postReloadBindSerial) return
    if (_postReloadBindSerial >= 0) {
      _postReloadBindSerial = -1
      _activeShortcut = null
    }
    var binds = Model.parseHyprctlBindsText(_bindsOutput)
    if (_bindsOutput.trim() && binds.length === 0) {
      _knownBinds = []
      _bindSnapshotReady = false
      shortcutConflict = "Could not safely inspect existing Hyprland shortcuts"
      return
    }
    _knownBinds = binds
    _bindSnapshotReady = true
    var hasOwnedBinding = binds.some(function(bind) { return root.ownBinding(bind) })
    var desired = Model.normalizeShortcut(settings.shortcut)
    if (!desired) {
      shortcutConflict = ""
      if (_mayOwnShortcut) runBindingCleanup("")
      return
    }

    var validation = validateShortcut(desired)
    if (validation) {
      shortcutConflict = validation
      if (_mayOwnShortcut) runBindingCleanup(validation)
      return
    }

    shortcutConflict = ""
    if (hasOwnedBinding && JSON.stringify(desired) === JSON.stringify(_activeShortcut)) return
    runBindingReplace(desired)
  }

  function shortcutChord(shortcut) {
    var parts = shortcut.modifiers.slice()
    parts.push("code:" + Number(shortcut.code))
    return parts.join(" + ")
  }

  function runBindingReplace(shortcut) {
    var chord = shortcutChord(shortcut)
    var command = "omarchy-shell -q qwitch nextLayout"
    var token = Model.luaQuote(_ownerToken)
    var generation = String(Math.floor(_ownerGeneration))
    var code = "do local generation = " + generation + "; local current = tonumber(rawget(_G, '__qwitch_generation') or 0); "
      + "local cancelled = tonumber(rawget(_G, '__qwitch_cancelled_generation') or 0); "
      + "if cancelled >= generation or generation < current then error('qwitch_stale') end; _G.__qwitch_generation = generation; "
      + "local old = rawget(_G, '__qwitch_owned_binding'); "
      + "if old ~= nil and (type(old) ~= 'table' or old.token ~= " + token + ") then error('qwitch_stale') end; "
      + "local old_handle = type(old) == 'table' and old.handle or nil; "
      + "if old_handle then local ok, result = pcall(function() return old_handle:unbind() end); "
      + "if not ok or result == false then error('qwitch_unbind_failed') end end; "
      + "if rawget(_G, '__qwitch_owned_binding') == old then _G.__qwitch_owned_binding = nil end; "
      + "local candidate = hl.bind(" + Model.luaQuote(chord) + ", hl.dsp.exec_cmd(" + Model.luaQuote(command) + "), { description = 'qwitch: Next layout' }); "
      + "_G.__qwitch_owned_binding = { token = " + token + ", handle = candidate }; "
      + "end"
    _pendingShortcut = shortcut
    _bindingOperation = "replace"
    _bindingEpoch = _runtimeEpoch
    _mayOwnShortcut = true
    _pendingBindingError = ""
    _actionError = ""
    var preLease = currentLeaseState("binding-replacing", true)
    var postLease = currentLeaseState("binding-active", true)
    bindingProcess.command = leasedCommand("eval", code, "", "", preLease, postLease)
    bindingProcess.running = true
  }

  function runBindingCleanup(preserveError) {
    _bindingOperation = "cleanup"
    _bindingEpoch = _runtimeEpoch
    _pendingBindingError = String(preserveError || "")
    _actionError = ""
    var token = Model.luaQuote(_ownerToken)
    var generation = String(Math.floor(_ownerGeneration))
    var code = "do local generation = " + generation + "; local current = tonumber(rawget(_G, '__qwitch_generation') or 0); "
      + "if generation >= current then _G.__qwitch_generation = generation; local owned = rawget(_G, '__qwitch_owned_binding'); "
      + "if type(owned) == 'table' and owned.token == " + token + " then local handle = owned.handle; "
      + "if handle then local ok, result = pcall(function() return handle:unbind() end); "
      + "if not ok or result == false then error('qwitch_unbind_failed') end end; "
      + "if rawget(_G, '__qwitch_owned_binding') == owned then _G.__qwitch_owned_binding = nil end end end end"
    var preLease = currentLeaseState("binding-removing", true)
    var postLease = currentLeaseState("binding-removed", false)
    bindingProcess.command = leasedCommand("eval", code, "", "", preLease, postLease)
    bindingProcess.running = true
  }

  function statusJson() {
    return JSON.stringify({
      layouts: layouts,
      activeIndex: activeIndex,
      mixed: mixedState,
      display: displayText,
      devices: devices,
      busy: busy,
      error: lastError,
      shortcutConflict: shortcutConflict,
      applicationMode: String(settings.applicationMode || "global"),
      activeApplicationId: activeApplicationId,
      rememberedApplications: Object.keys(settings.applicationLayouts || {}).length
    })
  }

  Process {
    id: bootstrapProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._runtimeOutput = String(text || "").trim() }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.lastError = String(text).trim() }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.lastError || "qwitch could not prepare its temporary runtime helper"
        return
      }
      root.beginDrain()
    }
  }

  Process {
    id: drainProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._runtimeOutput = String(text || "").trim() }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.lastError = String(text).trim() }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root._runtimeReady = false
        root._runtimeAwaitingFreshDevices = true
        root._runtimeReadyAfterSerial = root._deviceRefreshSerial
        root.lastError = ""
        root.refreshDevices(true)
        return
      }
      if (exitCode === 76) {
        var generation = /^generation:(\d+)$/.exec(root._runtimeOutput)
        if (generation) root.resetOwnerIdentity(Number(generation[1]))
        drainRetry.restart()
        return
      }
      root.lastError = root.lastError || "qwitch could not safely drain earlier runtime state"
    }
  }

  Process {
    id: abandonProcess
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.lastError = String(text).trim() }
    onExited: function(exitCode) {
      if (root.mutationSuperseded(exitCode)) {
        root.markSuperseded()
        return
      }
      if (exitCode !== 0) {
        root.lastError = root.lastError || "qwitch could not safely rebase after the Hyprland reload"
        if (exitCode !== 78) reloadAbandonRetry.restart()
        return
      }
      root._leaseMayExist = false
      if (root._reloadAbandonEpoch !== root._runtimeEpoch) {
        root._rebaseAfterSerial = root._deviceRefreshSerial
        reloadTimer.restart()
        return
      }

      root._rebaseAfterReload = false
      root._rebaseAfterSerial = -1
      root._reloadAbandonEpoch = -1
      root._baselines = ({})
      root._lastApplied = ({})
      root._pendingApplied = ({})
      root._pendingRestoreMatches = ({})
      root._restoreKeepBaselines = ({})
      root._restoreKeepApplied = ({})
      root._restoreKeepMatches = ({})
      root._restoreRetrying = false
      root._postRestoreRefresh = false
      root._restorePolicyAfterRefresh = false
      root._restoreAfterRefresh = false
      root._restoreReason = ""
      root._switchAfterRefresh = -1
      root._switchLeasePre = null
      root._switchLeasePost = null
      root._layoutPipeline = false
      root._activeShortcut = null
      root._mayOwnShortcut = false
      root._postReloadBindSerial = root._bindRefreshSerial
      root._runtimeReady = false
      root._runtimeAwaitingFreshDevices = true
      root._runtimeReadyAfterSerial = root._deviceRefreshSerial
      root._reconcilePending = true
      root._bindRefreshPending = true
      root.lastError = ""
      root.refreshDevices(true)
    }
  }

  Process {
    id: heartbeatProcess
    onExited: function(exitCode) {
      if (exitCode === 75) root.markSuperseded()
      else if (exitCode !== 0 && exitCode !== 78)
        root.lastError = "qwitch could not renew its runtime cleanup lease"
      else if (exitCode === 78)
        root.lastError = "qwitch found an unsafe or corrupt runtime cleanup lease"
    }
  }

  Process {
    id: catalogProcess
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._catalogOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.catalogError = String(text).trim() }
    onExited: function(exitCode) {
      root.catalogLoading = false
      if (exitCode === 0) {
        root.catalog = Model.parseXkbCatalog(root._catalogOutput)
        root.catalogError = root.catalog.length > 0 ? "" : "No XKB layouts were reported"
        root.recomputeLayouts()
      } else if (!root.catalogError) root.catalogError = "xkbcli could not list layouts"
    }
  }

  Process {
    id: nativeOptionProcess
    command: ["hyprctl", "-j", "getoption", "input:kb_options"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._nativeOptionOutput = text }
    onExited: function() {
      root._nativeOptionReady = true
      root.maybeAdoptExistingConfig()
    }
  }

  Process {
    id: procInputProcess
    command: ["cat", "/proc/bus/input/devices"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._procInputOutput = text }
    onExited: function() {
      root._procDevices = Model.parseProcInputDevices(root._procInputOutput)
      root._devicesOutput = ""
      devicesProcess.running = true
    }
  }

  Process {
    id: devicesProcess
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._devicesOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.lastError = String(text).trim() }
    onExited: function(exitCode) {
      if (exitCode === 0) root.consumeDeviceOutput()
      else {
        root.lastError = root.lastError || "hyprctl could not read input devices"
        root._restoreAfterRefresh = false
        root._switchAfterRefresh = -1
        root._layoutPipeline = false
        root.finishDeviceRefresh()
        root.finishMutation()
      }
    }
  }

  Process {
    id: layoutProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._actionError = String(text || "").trim() }
    onExited: function(exitCode) {
      if (root.mutationSuperseded(exitCode)) {
        root.markSuperseded()
        return
      }
      if (exitCode !== 0) {
        root.lastError = root._actionError || "Could not update keyboard layouts"
        if (root._layoutOperation === "apply") {
          // A Lua block can fail after an earlier device write. Refresh first,
          // then compare each device with the intended value before restoring.
          root._lastApplied = root._pendingApplied
          root._pendingApplied = ({})
          root._restoreAfterRefresh = true
          root._restoreReason = "Incomplete layout update"
          root._layoutOperation = ""
          Qt.callLater(function() { root.refreshDevices(true) })
        } else if (root._layoutOperation === "restore") {
          root._restoreRetrying = true
          root._layoutOperation = ""
          root._layoutPipeline = false
          root.refreshDevices()
          root.finishMutation()
        } else {
          root._layoutOperation = ""
          root._layoutPipeline = false
          root.finishMutation()
        }
        return
      }

      if (root._layoutOperation === "restore" || root._layoutOperation === "release") {
        root.completeLayoutRestore()
        return
      }

      root._lastApplied = root._pendingApplied
      root._pendingApplied = ({})
      root._pendingRestoreMatches = ({})
      root._layoutOperation = ""
      root._switchAfterRefresh = root._targetAfterApply
      Qt.callLater(function() { root.refreshDevices(true) })
    }
  }

  Process {
    id: switchProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._actionError = String(text || "").trim() }
    onExited: function(exitCode) {
      if (root.mutationSuperseded(exitCode)) {
        root.markSuperseded()
        return
      }
      if (exitCode === 0) {
        root.lastError = ""
        root.updateDevicesAfterSwitch(root._switchTarget)
        if (root._rememberApplicationAfterSwitch)
          root.rememberApplicationLayout(root._switchTarget, root._switchApplicationId)
        root._rememberApplicationAfterSwitch = false
        root._switchApplicationId = ""
        if (root._showOsdAfterSwitch) root.showLayoutOsd()
        root._layoutPipeline = false
        root.refreshDevices()
        root.finishMutation()
        return
      }

      root.lastError = root._actionError || "Could not switch every managed keyboard"
      root._rememberApplicationAfterSwitch = false
      root._switchApplicationId = ""
      var rollback = root.switchBatch(root._switchPrevious)
      if (rollback) {
        var rollbackApplied = root.appliedAtIndexes(root._switchPrevious)
        var rollbackPost = root.leaseState("layout-active", root._baselines,
          rollbackApplied, ({}), ({}), root._mayOwnShortcut)
        rollbackProcess.command = root.leasedCommand("eval-then-batch",
          root.ownershipGuardCode(), rollback, "", root._switchLeasePre, rollbackPost)
        rollbackProcess.running = true
      } else {
        root._layoutPipeline = false
        root.refreshDevices()
        root.finishMutation()
      }
    }
  }

  Process {
    id: rollbackProcess
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.lastError = String(text).trim() }
    onExited: function(exitCode) {
      if (root.mutationSuperseded(exitCode)) {
        root.markSuperseded()
        return
      }
      root._layoutPipeline = false
      root.refreshDevices()
      root.finishMutation()
    }
  }

  Process {
    id: bindsProcess
    // Hyprland 0.56 drops physical `code:N` values from JSON, while the text
    // listing preserves the complete display chord.
    command: ["hyprctl", "binds"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._bindsOutput = text }
    onExited: function(exitCode) {
      if (exitCode === 0) root.consumeBinds()
      else {
        root._bindSnapshotReady = false
        root.shortcutConflict = "Could not inspect existing Hyprland shortcuts"
      }
      if (root._bindRefreshPending) Qt.callLater(root.refreshBinds)
    }
  }

  Process {
    id: bindingProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._actionError = String(text || "").trim() }
    onExited: function(exitCode) {
      if (root.mutationSuperseded(exitCode)) {
        root.markSuperseded()
        return
      }
      var currentEpoch = root._bindingEpoch === root._runtimeEpoch
      if (exitCode === 0) {
        if (!currentEpoch) {
          root._activeShortcut = null
        } else if (root._bindingOperation === "replace") {
          root._activeShortcut = root._pendingShortcut
          root._mayOwnShortcut = true
          root.shortcutConflict = ""
        }
        else {
          root._activeShortcut = null
          root._mayOwnShortcut = false
          root.shortcutConflict = root._pendingBindingError
        }
      } else root.shortcutConflict = root._actionError || "Could not register the qwitch shortcut"
      root._bindingOperation = ""
      root._pendingBindingError = ""
      if (exitCode === 0) root.updateLeasePresence()
      if (!currentEpoch) {
        root._bindRefreshPending = true
      }
      if (root._rebaseAfterReload)
        Qt.callLater(function() { root.refreshDevices(true) })
      if (root._bindRefreshPending) Qt.callLater(root.refreshBinds)
      root.finishMutation()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "configreloaded") {
        root._runtimeEpoch += 1
        root._rebaseAfterReload = true
        root._rebaseAfterSerial = root._deviceRefreshSerial
        root._postReloadBindSerial = root._bindRefreshSerial
        root._activeShortcut = null
        root._showOsdAfterExternalRefresh = false
        root._adoptionAttempted = false
        root._nativeOptionReady = false
        if (!nativeOptionProcess.running) nativeOptionProcess.running = true
        reloadTimer.restart()
      } else if (name.indexOf("activelayout") !== -1 || name.indexOf("device") !== -1) {
        if (name.indexOf("activelayout") !== -1 && root._runtimeReady
            && !root._layoutPipeline && !root._showOsdAfterExternalRefresh) {
          root._externalRefreshPreviousIndex = root.activeIndex
          root._externalRefreshPreviousMixed = root.mixedState
          root._showOsdAfterExternalRefresh = true
        }
        refreshTimer.restart()
      }
    }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.refreshActiveApplication() }
  }

  Connections {
    target: ToplevelManager.activeToplevel
    ignoreUnknownSignals: true
    function onAppIdChanged() { root.refreshActiveApplication() }
  }

  Timer {
    id: refreshTimer
    interval: 250
    onTriggered: root.refreshDevices()
  }

  Timer {
    id: applicationLayoutTimer
    interval: 120
    onTriggered: root.applyRememberedApplicationLayout()
  }

  Timer {
    id: reloadTimer
    interval: 500
    onTriggered: {
      root.refreshDevices()
      root.refreshBinds()
    }
  }

  Timer {
    id: drainRetry
    interval: 250
    onTriggered: root.beginDrain()
  }

  Timer {
    id: reloadAbandonRetry
    interval: 500
    onTriggered: root.beginReloadAbandon()
  }

  Timer {
    interval: 2000
    running: root._runtimeReady && root._leaseMayExist && !root._superseded
    repeat: true
    onTriggered: {
      if (heartbeatProcess.running) return
      heartbeatProcess.command = [root._residentRuntimeHelper, "heartbeat",
        root._leaseId, root._ownerToken, String(Math.floor(root._ownerGeneration))]
      heartbeatProcess.running = true
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refreshDevices()
  }

  IpcHandler {
    target: "qwitch"

    function nextLayout(): string {
      return root.cycleNext() ? "ok" : "unavailable"
    }

    function state(): string {
      return root.statusJson()
    }

    function refresh(): string {
      root.refreshDevices()
      return "ok"
    }
  }

  Component.onCompleted: {
    resetOwnerIdentity(_ownerGeneration)
    _runtimeOutput = ""
    bootstrapProcess.command = [_bundledRuntimeHelper, "bootstrap"]
    bootstrapProcess.running = true
    refreshCatalog()
    refreshDevices()
    nativeOptionProcess.running = true
    Qt.callLater(root.refreshActiveApplication)
  }

  onShellChanged: {
    integrateWithOmarchyBar()
    maybeAdoptExistingConfig()
  }

  Component.onDestruction: retireLease()
}
