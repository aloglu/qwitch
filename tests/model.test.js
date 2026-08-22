'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const Model = require('../Model.js');

const XKB_CATALOG = `models:
- name: pc105
  vendor: Generic
  description: Generic 105-key PC
layouts:
- layout: 'us'
  variant: ''
  brief: 'en'
  description: English (US)
  iso639: ['eng']
  iso3166: ['US']
- layout: 'de'
  variant: 'nodeadkeys'
  brief: 'de'
  description: German (no dead keys)
  iso639: ['deu']
  iso3166: ['DE']
- layout: 'ara'
  variant: ''
  brief: 'ar'
  description: "Arabic: standard"
  iso639: ['ara']
  iso3166: ['AE', 'EG', 'SA']
- layout: 'epo'
  variant: ''
  brief: 'eo'
  description: 'Esperanto''s standard layout'
  iso639: ['epo']
  iso3166: []
options:
- name: grp:alt_shift_toggle
  description: Alt+Shift
`;

// Captured in the same shape as Linux's /proc/bus/input/devices. It contains
// one typing interface and the non-typing interfaces exposed by the same
// composite Wooting device, plus a YubiKey that advertises itself as a kbd.
const PROC_INPUT_FIXTURE = `I: Bus=0019 Vendor=0000 Product=0001 Version=0000
N: Name="Power Button"
P: Phys=PNP0C0C/button/input0
S: Sysfs=/devices/platform/PNP0C0C:00/input/input0
U: Uniq=
H: Handlers=kbd event0
B: PROP=0
B: EV=3
B: KEY=8000 10000000000000 0

I: Bus=0003 Vendor=31e3 Product=1402 Version=0111
N: Name="Wooting Wooting 80HE"
P: Phys=usb-0000:78:00.0-1/input1
S: Sysfs=/devices/pci0000:00/0000:78:00.0/usb5/5-1/5-1:1.1/0003:31E3:1402.0002/input/input2
U: Uniq=A02B2506W08T00100S03H13041
H: Handlers=sysrq kbd leds event2
B: PROP=0
B: EV=120013
B: KEY=1000000000007 ff980000000007ff febeffdfffefffff fffffffffffffffe
B: MSC=10
B: LED=1f

I: Bus=0003 Vendor=31e3 Product=1402 Version=0111
N: Name="Wooting Wooting 80HE System Control"
P: Phys=usb-0000:78:00.0-1/input3
S: Sysfs=/devices/pci0000:00/0000:78:00.0/usb5/5-1/5-1:1.3/0003:31E3:1402.0004/input/input3
U: Uniq=A02B2506W08T00100S03H13041
H: Handlers=kbd event3
B: PROP=0
B: EV=13
B: KEY=c000 10000000000000 0
B: MSC=10

I: Bus=0003 Vendor=31e3 Product=1402 Version=0111
N: Name="Wooting Wooting 80HE Consumer Control"
P: Phys=usb-0000:78:00.0-1/input3
S: Sysfs=/devices/pci0000:00/0000:78:00.0/usb5/5-1/5-1:1.3/0003:31E3:1402.0004/input/input4
U: Uniq=A02B2506W08T00100S03H13041
H: Handlers=kbd event4
B: PROP=0
B: EV=1f
B: KEY=733fff 0 0 483ffff17aff32d bfd4444600000000 1 130ff38b17d000 677bfad9415fed
B: REL=1040
B: ABS=100000000
B: MSC=10

I: Bus=0003 Vendor=31e3 Product=1402 Version=0111
N: Name="Wooting Wooting 80HE Mouse"
P: Phys=usb-0000:78:00.0-1/input3
S: Sysfs=/devices/pci0000:00/0000:78:00.0/usb5/5-1/5-1:1.3/0003:31E3:1402.0004/input/input5
U: Uniq=A02B2506W08T00100S03H13041
H: Handlers=event5 mouse0
B: PROP=0
B: EV=17
B: KEY=1f0000 0 0 0 0
B: REL=3
B: MSC=10

I: Bus=0003 Vendor=1050 Product=0407 Version=0110
N: Name="Yubico YubiKey OTP+FIDO+CCID"
P: Phys=usb-0000:14:00.0-2.3/input0
S: Sysfs=/devices/pci0000:00/0000:14:00.0/usb3/3-2/3-2.3/3-2.3:1.0/0003:1050:0407.0013/input/input26
U: Uniq=
H: Handlers=sysrq kbd leds event7
B: PROP=0
B: EV=120013
B: KEY=e080ffdf01cfffff fffffffffffffffe
B: MSC=10
B: LED=1f

I: Bus=0003 Vendor=046d Product=40a9 Version=0111
N: Name="Logitech PRO X 2"
P: Phys=usb-0000:14:00.0-2.4/input2:1
S: Sysfs=/devices/usb/0003:046D:40A9.0012/input/input16
U: Uniq=f8-8a-3c-b5
H: Handlers=sysrq kbd leds event9 mouse2
B: PROP=0
B: EV=12001f
B: KEY=3f00733fff 0 0 483ffff17aff32d bfd4444600000000 ffff0001 130ff38b17d007
B: REL=1943
B: ABS=100000000
B: MSC=10
B: LED=1f
`;

test('parses only the XKB layout catalog and derives safe defaults', () => {
  const catalog = Model.parseXkbCatalog(XKB_CATALOG);

  assert.equal(catalog.length, 4);
  assert.deepEqual(catalog[0], {
    layout: 'us',
    variant: '',
    brief: 'en',
    description: 'English (US)',
    iso639: ['eng'],
    iso3166: ['US'],
    label: 'EN',
    flag: '🇺🇸',
  });
  assert.equal(catalog[1].variant, 'nodeadkeys');
  assert.equal(catalog[1].flag, '🇩🇪');
  assert.equal(catalog[2].description, 'Arabic: standard');
  assert.equal(catalog[2].flag, '', 'a multinational layout must not get an arbitrary country flag');
  assert.equal(catalog[3].description, "Esperanto's standard layout");
});

test('normalizes entries against catalog metadata and preserves explicit edits', () => {
  const catalog = Model.parseXkbCatalog(XKB_CATALOG);

  assert.deepEqual(Model.normalizeLayoutEntry({ layout: 'de', variant: 'nodeadkeys' }, catalog), {
    layout: 'de', variant: 'nodeadkeys', label: 'DE', flag: '🇩🇪',
  });
  assert.deepEqual(Model.normalizeLayoutEntry({
    layout: 'de', variant: 'nodeadkeys', label: 'Deutsch', flag: '',
  }, catalog), {
    layout: 'de', variant: 'nodeadkeys', label: 'Deutsch', flag: '',
  });
  assert.equal(Model.normalizeLayoutEntry({ layout: 'us;rm', variant: '' }, catalog), null);
  assert.equal(Model.normalizeLayoutEntry({ layout: 'us', variant: '../../evil' }, catalog), null);
});

test('deduplicates layouts in first-seen order', () => {
  const layouts = Model.uniqueLayouts([
    { layout: 'de', variant: '', label: 'DE first', flag: '' },
    { layout: 'us', variant: '', label: 'EN', flag: '' },
    { layout: 'de', variant: '', label: 'DE second', flag: '' },
    { layout: 'de', variant: 'nodeadkeys', label: 'DE ND', flag: '' },
  ]);

  assert.deepEqual(layouts.map(({ layout, variant, label }) => [layout, variant, label]), [
    ['de', '', 'DE first'],
    ['us', '', 'EN'],
    ['de', 'nodeadkeys', 'DE ND'],
  ]);
});

test('sanitizes settings without inventing a default layout', () => {
  const dirty = {
    layouts: [
      { layout: 'us', variant: '', label: 'EN', flag: '🇺🇸' },
      { layout: 'us', variant: '', label: 'duplicate', flag: '' },
      { layout: 'de\nexec', variant: '', label: 'bad', flag: '' },
    ],
    displayMode: 'icons-and-confetti',
    osdEnabled: 'true',
    shortcut: { modifiers: ['SUPER'], key: 'K', code: 37 },
    nativeXkbOption: 'grp:alt_shift_toggle',
    deviceOverrides: JSON.parse('{"good":"manage","ignored":"ignore","bad":"maybe","__proto__":"manage"}'),
  };

  const clean = Model.sanitizeSettings(dirty);
  assert.equal(clean.layouts.length, 1);
  assert.equal(clean.displayMode, 'both');
  assert.equal(clean.osdEnabled, false);
  assert.equal(Object.hasOwn(clean, 'shortcut'), false);
  assert.equal(Object.hasOwn(clean, 'nativeXkbOption'), false);
  assert.deepEqual(clean.deviceOverrides, { good: 'manage', ignored: 'ignore' });

  const first = Model.defaultSettings();
  const second = Model.defaultSettings();
  first.layouts.push({ layout: 'us' });
  assert.deepEqual(second.layouts, []);
  assert.deepEqual(Model.sanitizeSettings(null), second);
});

test('sanitizes and resolves per-application layout memory', () => {
  const layouts = [
    { layout: 'us', variant: '', label: 'EN', flag: '' },
    { layout: 'tr', variant: 'f', label: 'TR', flag: '' },
  ];
  const usKey = Model.layoutKey(layouts[0]);
  const trKey = Model.layoutKey(layouts[1]);
  const clean = Model.sanitizeSettings({
    layouts,
    applicationMode: 'remember',
    applicationLayouts: {
      'Org.Alacritty': usKey,
      firefox: trKey,
      stale: 'de\u0000',
      '__proto__': trKey,
    },
  });

  assert.equal(clean.layoutScope, 'application');
  assert.equal(clean.applicationMode, undefined);
  assert.deepEqual(clean.applicationLayouts, {
    'org.alacritty': usKey,
    firefox: trKey,
  });
  assert.equal(Model.applicationLayoutIndex(clean.applicationLayouts,
    'ORG.ALACRITTY', clean.layouts), 0);
  assert.equal(Model.applicationLayoutIndex(clean.applicationLayouts,
    'firefox', clean.layouts), 1);
  assert.equal(Model.applicationLayoutIndex(clean.applicationLayouts,
    'unknown', clean.layouts), -1);
  assert.equal(Model.sanitizeSettings({ layoutScope: 'window' }).layoutScope, 'window');
  assert.equal(Model.sanitizeSettings({ layoutScope: 'automatic' }).layoutScope, 'global');
});

test('keeps independent layout memories for live window identities', () => {
  const layouts = [
    { layout: 'us', variant: '', label: 'EN', flag: '' },
    { layout: 'tr', variant: '', label: 'TR', flag: '' },
  ];
  const memories = Model.sanitizeLayoutMemories({
    '0xabc': Model.layoutKey(layouts[0]),
    '0xdef': Model.layoutKey(layouts[1]),
    '0x0': 'missing',
  }, layouts);

  assert.equal(Model.rememberedLayoutIndex(memories, '0xabc', layouts), 0);
  assert.equal(Model.rememberedLayoutIndex(memories, '0xdef', layouts), 1);
  assert.equal(Model.rememberedLayoutIndex(memories, '0x123', layouts), -1);
  assert.equal(Model.normalizeWindowAddress('557926f25050'), '0x557926f25050');
  assert.equal(Model.normalizeWindowAddress('0x557926F25050'), '0x557926f25050');
  assert.equal(Model.normalizeWindowAddress('00000000000000ab'), '0xab');
  assert.equal(Model.normalizeWindowAddress('0x0'), '');
  assert.equal(Model.normalizeWindowAddress('not-an-address'), '');
});

test('reads native Hyprland XKB options and labels common group toggles', () => {
  assert.equal(Model.parseHyprOptionString('{"str":"caps:escape,grp:alt_shift_toggle"}'),
    'caps:escape,grp:alt_shift_toggle');
  assert.equal(Model.parseHyprOptionString('not json'), '');
  assert.equal(Model.firstGroupToggle('caps:escape,grp:alt_shift_toggle'), 'grp:alt_shift_toggle');
  assert.equal(Model.nativeXkbShortcutLabel('grp:alt_shift_toggle'), 'Alt + Shift');
  assert.equal(Model.nativeXkbShortcutLabel('grp:win_space_toggle'), 'Super + Space');
  assert.equal(Model.nativeXkbShortcutLabel('grp:ctrl_alt_toggle'), 'Ctrl + Alt');
  assert.equal(Model.firstGroupToggle('caps:escape'), '');
  assert.equal(Model.firstGroupToggle('caps:escape,grp:unknown_toggle,grp:ctrl_shift_toggle'),
    'grp:ctrl_shift_toggle');
  assert.equal(Model.nativeXkbShortcutLabel('grp:unknown_toggle'), '');

  const adopted = Model.sanitizeSettings({
    adoptedExistingConfig: true,
    nativeXkbOption: 'grp:ctrl_shift_toggle',
  });
  assert.equal(adopted.adoptedExistingConfig, true);
  assert.equal(Object.hasOwn(adopted, 'nativeXkbOption'), false);
});

test('formats text, flags and fallbacks without leaving an empty widget', () => {
  const entry = { layout: 'us', variant: '', label: 'EN', flag: '🇺🇸' };
  assert.equal(Model.displayForLayout(entry, 'text'), 'EN');
  assert.equal(Model.displayForLayout(entry, 'flag'), '🇺🇸');
  assert.equal(Model.displayForLayout(entry, 'both'), '🇺🇸 EN');
  assert.equal(Model.displayForLayout({ layout: 'ara', variant: '', label: 'AR', flag: '' }, 'flag'), 'AR');
  assert.equal(Model.displayForLayout({ layout: 'ara', variant: '', label: '', flag: '' }, 'both'), 'ARA');
  assert.equal(Model.regionalFlag('tr'), '🇹🇷');
  assert.equal(Model.regionalFlag('eng'), '');
});

test('quotes arbitrary strings as a single Lua string literal', () => {
  assert.equal(Model.luaQuote('plain'), '"plain"');
  assert.equal(Model.luaQuote('a"b\\c\n\t\0'), '"a\\"b\\\\c\\n\\t\\000"');
  assert.equal(Model.luaQuote('"; os.execute("bad") --'), '"\\\"; os.execute(\\\"bad\\\") --"');
  assert.equal(Model.luaQuote('İstanbul 🇹🇷'), '"İstanbul 🇹🇷"');
});

test('parses real-style kernel input records', () => {
  const devices = Model.parseProcInputDevices(PROC_INPUT_FIXTURE);
  assert.equal(devices.length, 7);

  const wooting = devices[1];
  assert.equal(wooting.bus, '0003');
  assert.equal(wooting.vendor, '31e3');
  assert.equal(wooting.product, '1402');
  assert.equal(wooting.uniq, 'A02B2506W08T00100S03H13041');
  assert.deepEqual(wooting.handlers, ['sysrq', 'kbd', 'leds', 'event2']);
  assert.equal(wooting.capabilities.LED, '1f');

  assert.equal(Model.matchInputDevice('wooting-wooting-80he', devices), wooting);
  assert.equal(Model.matchInputDevice('Yubico-YubiKey-OTP-FIDO-CCID', devices), devices[5]);
  assert.equal(Model.matchInputDevice('not-a-real-device', devices), null);
});

test('fails closed when a normalized input name is not unique', () => {
  const devices = Model.parseProcInputDevices(PROC_INPUT_FIXTURE);
  const duplicate = { ...devices[1] };
  assert.equal(Model.matchInputDevice('wooting-wooting-80he', devices.concat(duplicate)), null);
});

test('classifies only a high-confidence typing interface automatically', () => {
  const devices = Model.parseProcInputDevices(PROC_INPUT_FIXTURE);
  const runtime = (name) => ({ name });

  const typing = Model.classifyDevice(runtime('wooting-wooting-80he'), devices[1]);
  assert.equal(typing.managed, true);
  assert.equal(typing.security, false);
  assert.equal(typing.ambiguous, false);
  assert.equal(typing.runtimeName, 'wooting-wooting-80he');
  assert.equal(typing.label, 'Wooting Wooting 80HE');
  assert.match(typing.fingerprint, /^v1:31e3:1402:serial:/);

  const system = Model.classifyDevice(runtime('wooting-wooting-80he-system-control'), devices[2]);
  const consumer = Model.classifyDevice(runtime('wooting-wooting-80he-consumer-control'), devices[3]);
  const mouse = Model.classifyDevice(runtime('wooting-wooting-80he-mouse'), devices[4]);
  const token = Model.classifyDevice(runtime('yubico-yubikey-otp-fido-ccid'), devices[5]);
  const mixedHeadset = Model.classifyDevice(runtime('logitech-pro-x-2'), devices[6]);

  assert.deepEqual([system.managed, consumer.managed, mouse.managed, mixedHeadset.managed], [false, false, false, false]);
  assert.equal(system.category, 'control');
  assert.equal(consumer.category, 'control');
  assert.equal(mouse.category, 'pointer');
  assert.equal(mixedHeadset.category, 'pointer');
  assert.equal(token.managed, false);
  assert.equal(token.security, true);
  assert.match(token.reason, /security/i);

  assert.notEqual(typing.fingerprint, system.fingerprint, 'composite roles must not share overrides');
  assert.equal(typing.fingerprint.includes('event2'), false, 'event handler numbers are not stable identity');

  const narrow = {
    ...devices[1],
    name: 'Generic USB Keyboard',
    uniq: 'scanner-1',
    handlers: ['kbd', 'event20'],
    capabilities: { KEY: 'ffff' },
  };
  const keyboardNamedOnly = Model.classifyDevice(runtime('generic-usb-keyboard'), narrow);
  assert.equal(keyboardNamedOnly.managed, false, 'a keyboard-like product name is not typing evidence');
  assert.equal(keyboardNamedOnly.ambiguous, true);
});

test('applies ignore before manage and marks unsafe forced management', () => {
  const devices = Model.parseProcInputDevices(PROC_INPUT_FIXTURE);
  const keyboard = { name: 'yubico-yubikey-otp-fido-ccid' };

  const ignored = Model.classifyDevice(keyboard, devices[5], { ignore: true, manage: true });
  assert.equal(ignored.managed, false);
  assert.equal(ignored.source, 'override');

  const forced = Model.classifyDevice(keyboard, devices[5], 'manage');
  assert.equal(forced.managed, true);
  assert.equal(forced.security, true);
  assert.equal(forced.requiresConfirmation, true);

  const noKernelMatch = Model.classifyDevice({ name: 'mystery-keyboard' }, null, undefined);
  assert.equal(noKernelMatch.managed, false);
  assert.equal(noKernelMatch.ambiguous, true);
});
