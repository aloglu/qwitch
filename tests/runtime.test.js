const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const test = require("node:test")
const { spawnSync } = require("node:child_process")

const helper = path.join(__dirname, "..", "qwitch-runtime")

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "qwitch-runtime-test."))
  const log = path.join(root, "hypr.log")
  const devices = path.join(root, "devices.json")
  const proc = path.join(root, "proc-input")
  const fake = path.join(root, "hyprctl")
  fs.writeFileSync(fake, `#!/usr/bin/env bash
set -u
printf '%s\\n' "$*" >>"$FAKE_LOG"
if [[ \${FAKE_SLEEP_SECONDS:-0} != 0 ]]; then /usr/bin/sleep "$FAKE_SLEEP_SECONDS"; fi
if [[ \${1:-} == -j && \${2:-} == devices ]]; then
  /usr/bin/cat "$FAKE_DEVICES"
  exit 0
fi
if [[ \${1:-} == eval && \${FAKE_EVAL_FAIL:-0} == 1 ]]; then exit 1; fi
exit 0
`)
  fs.chmodSync(fake, 0o755)
  fs.writeFileSync(log, "")
  fs.writeFileSync(devices, JSON.stringify({ keyboards: [] }))
  fs.writeFileSync(proc, "")
  const env = {
    ...process.env,
    XDG_RUNTIME_DIR: root,
    qwitch_hyprctl: fake,
    qwitch_proc_input: proc,
    qwitch_test_mode: "1",
    qwitch_test_disable_guardian: "1",
    HYPRLAND_INSTANCE_SIGNATURE: "fake-hypr",
    FAKE_LOG: log,
    FAKE_DEVICES: devices
  }
  return { root, log, devices, proc, env }
}

function identity(overrides = {}) {
  return {
    inputName: "Wooting Wooting 80HE",
    bus: "0003",
    vendor: "31e3",
    product: "1312",
    uniq: "ABC123",
    phys: "usb-0000:00:14.0-1/input0",
    ...overrides
  }
}

function lease(overrides = {}) {
  return {
    schema: 2,
    leaseId: "lease-200",
    token: "qwitch-200-test",
    generation: 200,
    hyprInstance: "fake-hypr",
    status: "active",
    phase: "active",
    heartbeat: 0,
    devices: [{
      fingerprint: "v1:31e3:1312:serial:abc123",
      name: "wooting-wooting-80he",
      identity: identity(),
      baseline: { layout: "us", variant: "", index: 0 },
      ownedLayouts: [{ layout: "us,de", variant: ",nodeadkeys" }],
      ownedIndexes: [1]
    }],
    ...overrides
  }
}

function run(ctx, args, env = {}) {
  return spawnSync(ctx.executable || helper, args, {
    env: { ...ctx.env, ...env },
    encoding: "utf8"
  })
}

function arm(ctx, pre, post = pre, env = {}) {
  return run(ctx, ["mutate", pre.leaseId, pre.token, String(pre.generation),
    JSON.stringify(pre), JSON.stringify(post), "eval", "do end", "", ""], env)
}

function pause(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds)
}

function waitFor(predicate, timeout = 3000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    if (predicate()) return true
    pause(20)
  }
  return predicate()
}

function writeProc(ctx, values = identity()) {
  fs.writeFileSync(ctx.proc, `I: Bus=${values.bus} Vendor=${values.vendor} Product=${values.product} Version=0111
N: Name="${values.inputName}"
P: Phys=${values.phys}
S: Sysfs=/devices/fake/input0
U: Uniq=${values.uniq}
H: Handlers=sysrq kbd event0 leds
B: KEY=ffffffff ffffffff ffffffff ffffffff ffffffff ffffffff

`)
}

test("failed mutation retains the conservative pre-state", () => {
  const ctx = setup()
  const pre = lease({ phase: "layout-switching" })
  const post = lease({ phase: "layout-active" })
  const result = arm(ctx, pre, post, { FAKE_EVAL_FAIL: "1" })
  assert.equal(result.status, 1)
  const saved = JSON.parse(fs.readFileSync(path.join(ctx.root, "qwitch", "lease-v2.json")))
  assert.equal(saved.phase, "layout-switching")
})

test("cleanup restores exact device layout and owned active index", () => {
  const ctx = setup()
  writeProc(ctx)
  fs.writeFileSync(ctx.devices, JSON.stringify({ keyboards: [{
    name: "wooting-wooting-80he", layout: "us,de", variant: ",nodeadkeys",
    active_layout_index: 1
  }] }))
  assert.equal(arm(ctx, lease()).status, 0)
  const cleaned = run(ctx, ["cleanup-now", "lease-200"])
  assert.equal(cleaned.status, 0, cleaned.stderr)
  const log = fs.readFileSync(ctx.log, "utf8")
  assert.match(log, /hl\.device\(\{ name = "wooting-wooting-80he", kb_layout = "us"/)
  assert.match(log, /--batch switchxkblayout wooting-wooting-80he 0/)
  assert.equal(fs.existsSync(path.join(ctx.root, "qwitch", "lease-v2.json")), false)
})

test("cleanup leaves an externally changed device and index untouched", () => {
  const ctx = setup()
  writeProc(ctx)
  fs.writeFileSync(ctx.devices, JSON.stringify({ keyboards: [{
    name: "wooting-wooting-80he", layout: "fr", variant: "oss",
    active_layout_index: 7
  }] }))
  assert.equal(arm(ctx, lease()).status, 0)
  assert.equal(run(ctx, ["cleanup-now", "lease-200"]).status, 0)
  const cleanupLog = fs.readFileSync(ctx.log, "utf8").split("\n").slice(1).join("\n")
  assert.doesNotMatch(cleanupLog, /hl\.device/)
  assert.doesNotMatch(cleanupLog, /--batch/)
})

test("same-name replacement is retained as a tombstone and never touched", () => {
  const ctx = setup()
  writeProc(ctx, identity({ vendor: "9999", product: "0001", uniq: "OTHER" }))
  fs.writeFileSync(ctx.devices, JSON.stringify({ keyboards: [{
    name: "wooting-wooting-80he", layout: "us,de", variant: ",nodeadkeys",
    active_layout_index: 1
  }] }))
  assert.equal(arm(ctx, lease()).status, 0)
  const cleaned = run(ctx, ["cleanup-now", "lease-200"])
  assert.equal(cleaned.status, 10)
  const saved = JSON.parse(fs.readFileSync(path.join(ctx.root, "qwitch", "lease-v2.json")))
  assert.equal(saved.phase, "collision-wait")
  const cleanupLog = fs.readFileSync(ctx.log, "utf8").split("\n").slice(1).join("\n")
  assert.doesNotMatch(cleanupLog, /hl\.device/)
  assert.doesNotMatch(cleanupLog, /--batch/)
})

test("absent device gets targeted layout restoration without an index switch", () => {
  const ctx = setup()
  assert.equal(arm(ctx, lease()).status, 0)
  assert.equal(run(ctx, ["cleanup-now", "lease-200"]).status, 0)
  const log = fs.readFileSync(ctx.log, "utf8")
  assert.match(log, /hl\.device/)
  assert.doesNotMatch(log, /--batch/)
})


test("successor drain retires the old lease before it can claim", () => {
  const ctx = setup()
  const state = lease()
  assert.equal(arm(ctx, state).status, 0)
  const drain = run(ctx, ["drain", "lease-300", "qwitch-300-next", "300"])
  assert.equal(drain.status, 76)
  const saved = JSON.parse(fs.readFileSync(path.join(ctx.root, "qwitch", "lease-v2.json")))
  assert.equal(saved.status, "retiring")
  assert.equal(saved.phase, "successor-drain")
})

test("retiring leases cannot be resurrected by the old service", () => {
  const ctx = setup()
  const state = lease()
  assert.equal(arm(ctx, state).status, 0)
  assert.equal(run(ctx, ["retire", state.leaseId, state.token, "200"]).status, 0)
  const before = fs.readFileSync(ctx.log, "utf8")
  assert.equal(arm(ctx, state).status, 75)
  assert.equal(fs.readFileSync(ctx.log, "utf8"), before)
  const saved = JSON.parse(fs.readFileSync(path.join(ctx.root, "qwitch", "lease-v2.json")))
  assert.equal(saved.status, "retiring")
})

test("mutation command and both payload identities must match exactly", () => {
  const ctx = setup()
  const pre = lease()
  const wrongToken = lease({ token: "qwitch-200-other" })
  assert.equal(arm(ctx, pre, wrongToken).status, 78)
  assert.equal(fs.existsSync(path.join(ctx.root, "qwitch", "lease-v2.json")), false)

  const wrongInstance = lease({ hyprInstance: "other-hypr" })
  assert.equal(arm(ctx, pre, wrongInstance).status, 78)
  assert.equal(fs.readFileSync(ctx.log, "utf8"), "")
})

test("a new compositor instance discards the inaccessible old lease", () => {
  const ctx = setup()
  assert.equal(arm(ctx, lease()).status, 0)
  const drained = run(ctx, ["drain", "lease-300", "qwitch-300-next", "300"], {
    HYPRLAND_INSTANCE_SIGNATURE: "new-fake-hypr"
  })
  assert.equal(drained.status, 0, drained.stderr)
  assert.equal(drained.stdout.trim(), "ready")
  assert.equal(fs.existsSync(path.join(ctx.root, "qwitch", "lease-v2.json")), false)
})

test("Hyprland command timeout retains the conservative pre-state", () => {
  const ctx = setup()
  const pre = lease({ phase: "layout-switching" })
  const post = lease({ phase: "layout-active" })
  const started = Date.now()
  const result = arm(ctx, pre, post, {
    FAKE_SLEEP_SECONDS: "2",
    qwitch_hypr_timeout_seconds: "1"
  })
  assert.equal(result.status, 1)
  assert.ok(Date.now() - started < 1800, "hyprctl timeout was not bounded")
  const saved = JSON.parse(fs.readFileSync(path.join(ctx.root, "qwitch", "lease-v2.json")))
  assert.equal(saved.phase, "layout-switching")
})

test("heartbeat is exact and increments only the active lease", () => {
  const ctx = setup()
  const state = lease()
  assert.equal(arm(ctx, state).status, 0)
  assert.equal(run(ctx, ["heartbeat", state.leaseId, state.token, "200"]).status, 0)
  const saved = JSON.parse(fs.readFileSync(path.join(ctx.root, "qwitch", "lease-v2.json")))
  assert.equal(saved.heartbeat, 1)
  assert.equal(run(ctx, ["heartbeat", "wrong", state.token, "200"]).status, 75)
})

test("stored leases require an exact service process identity", () => {
  const ctx = setup()
  const state = lease()
  assert.equal(arm(ctx, state).status, 0)
  const leasePath = path.join(ctx.root, "qwitch", "lease-v2.json")
  const saved = JSON.parse(fs.readFileSync(leasePath))
  assert.equal(typeof saved.shellPid, "number")
  assert.match(saved.shellStart, /^[1-9][0-9]*$/)
  delete saved.shellStart
  fs.writeFileSync(leasePath, JSON.stringify(saved), { mode: 0o600 })
  assert.equal(run(ctx, ["heartbeat", state.leaseId, state.token, "200"]).status, 78)
})


test("exact abandonment drops only the lease and never calls Hyprland", () => {
  const ctx = setup()
  const state = lease()
  assert.equal(arm(ctx, state).status, 0)
  const before = fs.readFileSync(ctx.log, "utf8")
  assert.equal(run(ctx, ["abandon", state.leaseId, state.token, "200", "wrong"]).status, 75)
  assert.equal(run(ctx, ["abandon", state.leaseId, state.token, "200", "fake-hypr"]).status, 0)
  assert.equal(fs.readFileSync(ctx.log, "utf8"), before)
  assert.equal(fs.existsSync(path.join(ctx.root, "qwitch", "lease-v2.json")), false)
})

test("resident guardian retires safely after checkout deletion and can be re-armed", () => {
  const ctx = setup()
  const checkout = path.join(ctx.root, "checkout")
  const source = path.join(checkout, "qwitch-runtime")
  fs.mkdirSync(checkout)
  fs.copyFileSync(helper, source)
  fs.chmodSync(source, 0o755)
  ctx.executable = source

  const guardianEnv = {
    qwitch_test_disable_guardian: "0",
    qwitch_test_guardian_poll_seconds: "0.2"
  }
  const bootstrap = run(ctx, ["bootstrap"], guardianEnv)
  assert.equal(bootstrap.status, 0, bootstrap.stderr)
  ctx.executable = bootstrap.stdout.trim()

  const state = lease({ devices: [] })
  assert.equal(arm(ctx, state, state, guardianEnv).status, 0)
  const stateDir = path.join(ctx.root, "qwitch")
  const ackPath = path.join(stateDir, `watchdog.${state.leaseId}.ack`)
  const firstAck = fs.readFileSync(ackPath, "utf8").trim().split(/\s+/)
  assert.equal(firstAck.length, 3)
  assert.match(firstAck[2], /^arm-/)

  fs.unlinkSync(source)
  assert.equal(run(ctx, ["retire", state.leaseId, state.token, "200"], guardianEnv).status, 0)
  assert.equal(waitFor(() => !fs.existsSync(path.join(stateDir, "lease-v2.json"))
    && !fs.existsSync(ackPath)), true)
  assert.doesNotMatch(fs.readFileSync(ctx.log, "utf8"), /handle:unbind|kb_options/)

  assert.equal(arm(ctx, state, state, guardianEnv).status, 0)
  const secondAck = fs.readFileSync(ackPath, "utf8").trim().split(/\s+/)
  assert.notEqual(secondAck[2], firstAck[2])
  assert.equal(run(ctx, ["retire", state.leaseId, state.token, "200"], guardianEnv).status, 0)
  assert.equal(waitFor(() => !fs.existsSync(ackPath)), true)
})

test("bootstrap replaces a stale resident helper with the bundled version", () => {
  const ctx = setup()
  const stateDir = path.join(ctx.root, "qwitch")
  const resident = path.join(stateDir, "qwitch-runtime-v2")
  fs.mkdirSync(stateDir, { mode: 0o700 })
  fs.writeFileSync(resident, "#!/usr/bin/env bash\nexit 99\n", { mode: 0o700 })

  const bootstrap = run(ctx, ["bootstrap"])
  assert.equal(bootstrap.status, 0, bootstrap.stderr)
  assert.equal(bootstrap.stdout.trim(), resident)
  assert.deepEqual(fs.readFileSync(resident), fs.readFileSync(helper))
  assert.equal(fs.statSync(resident).mode & 0o777, 0o700)
})

test("corrupt lease and symlinked runtime directory fail closed", () => {
  const ctx = setup()
  fs.mkdirSync(path.join(ctx.root, "qwitch"), { mode: 0o700 })
  fs.writeFileSync(path.join(ctx.root, "qwitch", "lease-v2.json"), "not-json\n", { mode: 0o600 })
  assert.equal(arm(ctx, lease()).status, 78)
  assert.equal(fs.readFileSync(ctx.log, "utf8"), "")

  const other = fs.mkdtempSync(path.join(os.tmpdir(), "qwitch-symlink-target."))
  const symlinkRoot = fs.mkdtempSync(path.join(os.tmpdir(), "qwitch-symlink-root."))
  fs.symlinkSync(other, path.join(symlinkRoot, "qwitch"))
  const result = spawnSync(helper, ["bootstrap"], {
    env: { ...process.env, XDG_RUNTIME_DIR: symlinkRoot }, encoding: "utf8"
  })
  assert.equal(result.status, 78)
})
