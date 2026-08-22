/*
 * qwitch model helpers.
 *
 * This file deliberately has no Qt imports so it can be used both from QML
 * (`import "Model.js" as Model`) and from the Node test suite.
 */

var DISPLAY_MODES = ["text", "flag", "both"];
var LAYOUT_SCOPES = ["global", "application", "window"];
var MODIFIER_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"];
var MODIFIER_BITS = {
    SHIFT: 1,
    CAPS: 2,
    CTRL: 4,
    ALT: 8,
    MOD2: 16,
    MOD3: 32,
    SUPER: 64,
    MOD5: 128
};

function own(object, key) {
    return object !== null && object !== undefined && Object.prototype.hasOwnProperty.call(object, key);
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function trimmed(value) {
    if (value === null || value === undefined)
        return "";
    return String(value).replace(/^\s+|\s+$/g, "");
}

function cleanText(value, maximumLength) {
    var result = trimmed(value).replace(/[\u0000-\u001f\u007f]/g, "");
    if (maximumLength && result.length > maximumLength)
        result = result.slice(0, maximumLength);
    return result;
}

function normalizeXkbName(value, allowEmpty) {
    var raw = trimmed(value);
    if (/[\u0000-\u001f\u007f]/.test(raw))
        return "";
    var result = cleanText(raw, 96);
    if (allowEmpty && result === "")
        return "";
    if (!/^[A-Za-z0-9][A-Za-z0-9_.+-]*$/.test(result))
        return "";
    return result;
}

function regionalFlag(countryCode) {
    var code = trimmed(countryCode).toUpperCase();
    if (!/^[A-Z]{2}$/.test(code))
        return "";

    function regionalLetter(character) {
        var point = 0x1f1e6 + character.charCodeAt(0) - 65;
        var offset = point - 0x10000;
        return String.fromCharCode(0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff));
    }

    return regionalLetter(code.charAt(0)) + regionalLetter(code.charAt(1));
}

function firstCountry(entry) {
    var countries = entry && (entry.iso3166 || entry.countries || entry.country);
    if (typeof countries === "string")
        countries = [countries];
    if (!Array.isArray(countries) || countries.length !== 1)
        return "";
    return regionalFlag(countries[0]);
}

function inferFlag(entry) {
    if (!entry)
        return "";

    var layout = trimmed(entry.layout);
    if (/^[A-Za-z]{2}$/.test(layout))
        return regionalFlag(layout);
    return firstCountry(entry);
}

function layoutKey(entry) {
    if (!entry)
        return "";
    var layout = normalizeXkbName(entry.layout, false);
    var variant = normalizeXkbName(entry.variant, true);
    if (!layout)
        return "";
    return layout + "\u0000" + variant;
}

function findCatalogEntry(layout, variant, catalog) {
    if (!Array.isArray(catalog))
        return null;
    for (var index = 0; index < catalog.length; index += 1) {
        var candidate = catalog[index];
        if (candidate && trimmed(candidate.layout) === layout && trimmed(candidate.variant) === variant)
            return candidate;
    }
    return null;
}

function normalizeLayoutEntry(value, catalog) {
    var source;
    if (typeof value === "string")
        source = { layout: value, variant: "" };
    else if (isObject(value))
        source = value;
    else
        return null;

    var layout = normalizeXkbName(source.layout, false);
    var variant = normalizeXkbName(source.variant, true);
    if (!layout || (trimmed(source.variant) !== "" && !variant))
        return null;

    var catalogEntry = findCatalogEntry(layout, variant, catalog);
    var metadata = catalogEntry || source;
    var labelSource = own(source, "label") ? source.label : (metadata.label || metadata.brief);
    var label = cleanText(labelSource, 16);
    if (!label)
        label = layout.toUpperCase();

    var flag;
    if (own(source, "flag"))
        flag = cleanText(source.flag, 16);
    else if (metadata && own(metadata, "flag"))
        flag = cleanText(metadata.flag, 16);
    else
        flag = inferFlag(metadata);

    return {
        layout: layout,
        variant: variant,
        label: label,
        flag: flag
    };
}

function uniqueLayouts(values, catalog) {
    if (!Array.isArray(values))
        return [];

    var result = [];
    var seen = {};
    for (var index = 0; index < values.length; index += 1) {
        var entry = normalizeLayoutEntry(values[index], catalog);
        var key = layoutKey(entry);
        var safeKey = "$" + key;
        if (!entry || own(seen, safeKey))
            continue;
        seen[safeKey] = true;
        result.push(entry);
    }
    return result;
}

function displayForLayout(entry, mode) {
    var normalized = normalizeLayoutEntry(entry);
    if (!normalized)
        return "";

    var displayMode = DISPLAY_MODES.indexOf(mode) >= 0 ? mode : "both";
    var text = normalized.label || normalized.layout.toUpperCase();
    var flag = normalized.flag;
    if (displayMode === "text")
        return text;
    if (displayMode === "flag")
        return flag || text;
    return flag ? flag + " " + text : text;
}

function parseInlineList(value) {
    var body = trimmed(value).slice(1, -1);
    if (!body)
        return [];

    var parts = [];
    var current = "";
    var quote = "";
    var escaped = false;
    for (var index = 0; index < body.length; index += 1) {
        var character = body.charAt(index);
        if (escaped) {
            current += character;
            escaped = false;
        } else if (quote === "\"" && character === "\\") {
            current += character;
            escaped = true;
        } else if (quote) {
            current += character;
            if (character === quote) {
                if (quote === "'" && body.charAt(index + 1) === "'") {
                    current += body.charAt(index + 1);
                    index += 1;
                } else {
                    quote = "";
                }
            }
        } else if (character === "'" || character === "\"") {
            quote = character;
            current += character;
        } else if (character === ",") {
            parts.push(parseYamlishValue(current));
            current = "";
        } else {
            current += character;
        }
    }
    parts.push(parseYamlishValue(current));
    return parts;
}

function parseYamlishValue(value) {
    var source = trimmed(value);
    if (source === "")
        return "";
    if (source.charAt(0) === "[" && source.charAt(source.length - 1) === "]")
        return parseInlineList(source);
    if (source.charAt(0) === "'" && source.charAt(source.length - 1) === "'")
        return source.slice(1, -1).replace(/''/g, "'");
    if (source.charAt(0) === "\"" && source.charAt(source.length - 1) === "\"") {
        try {
            return JSON.parse(source);
        } catch (error) {
            return source.slice(1, -1);
        }
    }
    if (source === "null" || source === "~")
        return "";
    return source;
}

function decorateCatalogEntry(raw) {
    var layout = normalizeXkbName(raw.layout, false);
    var variant = normalizeXkbName(raw.variant, true);
    if (!layout || (trimmed(raw.variant) !== "" && !variant))
        return null;

    var entry = {
        layout: layout,
        variant: variant,
        brief: cleanText(raw.brief, 16),
        description: cleanText(raw.description, 256),
        iso639: Array.isArray(raw.iso639) ? raw.iso639.slice() : [],
        iso3166: Array.isArray(raw.iso3166) ? raw.iso3166.slice() : []
    };
    entry.label = entry.brief ? entry.brief.toUpperCase() : layout.toUpperCase();
    entry.flag = inferFlag(entry);
    return entry;
}

function parseXkbCatalog(text) {
    var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n");
    var layouts = [];
    var inLayouts = false;
    var current = null;

    function finishCurrent() {
        if (!current)
            return;
        var decorated = decorateCatalogEntry(current);
        if (decorated)
            layouts.push(decorated);
        current = null;
    }

    for (var index = 0; index < lines.length; index += 1) {
        var line = lines[index];
        if (!inLayouts) {
            if (/^layouts:\s*$/.test(line))
                inLayouts = true;
            continue;
        }

        if (/^[A-Za-z][A-Za-z0-9_-]*:\s*/.test(line)) {
            finishCurrent();
            break;
        }

        var first = /^-\s+([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/.exec(line);
        if (first) {
            finishCurrent();
            current = {};
            current[first[1]] = parseYamlishValue(first[2]);
            continue;
        }

        var property = /^\s+([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/.exec(line);
        if (property && current)
            current[property[1]] = parseYamlishValue(property[2]);
    }
    finishCurrent();
    return layouts;
}

function modifierAlias(value) {
    var key = trimmed(value).toUpperCase().replace(/[ _-]+/g, "");
    var aliases = {
        SUPER: "SUPER",
        META: "SUPER",
        LOGO: "SUPER",
        WIN: "SUPER",
        WINDOWS: "SUPER",
        MOD4: "SUPER",
        CTRL: "CTRL",
        CONTROL: "CTRL",
        ALT: "ALT",
        MOD1: "ALT",
        SHIFT: "SHIFT",
        CAPS: "CAPS",
        CAPSLOCK: "CAPS",
        MOD2: "MOD2",
        NUM: "MOD2",
        NUMLOCK: "MOD2",
        MOD3: "MOD3",
        MOD5: "MOD5"
    };
    return aliases[key] || "";
}

function modifierValues(value) {
    if (Array.isArray(value))
        return value.slice();
    if (typeof value === "string")
        return value.split(/[+,|\s]+/).filter(function(part) { return part !== ""; });
    return [];
}

function modifiersFromMask(mask) {
    var number = Number(mask);
    if (!isFinite(number) || number < 0)
        return [];
    var result = [];
    for (var index = 0; index < MODIFIER_ORDER.length; index += 1) {
        var name = MODIFIER_ORDER[index];
        if ((number & MODIFIER_BITS[name]) !== 0)
            result.push(name);
    }
    return result;
}

function shortcutModifierInput(value) {
    if (!isObject(value))
        return [];
    var result = [];
    if (own(value, "modifiers"))
        result = result.concat(modifierValues(value.modifiers));
    else if (own(value, "mods"))
        result = result.concat(modifierValues(value.mods));
    else if (own(value, "modifier"))
        result = result.concat(modifierValues(value.modifier));
    if (own(value, "modmask"))
        result = result.concat(modifiersFromMask(value.modmask));

    // Hyprland 0.56's JSON output can omit the physical chord. Its text
    // output retains forms such as `SUPER + CTRL + code:10`, so accept the
    // modifier tokens embedded in a parsed key field as well.
    if (typeof value.key === "string" && value.key.indexOf("+") >= 0) {
        var chordParts = value.key.split("+");
        for (var index = 0; index < chordParts.length; index += 1) {
            if (modifierAlias(chordParts[index]))
                result.push(chordParts[index]);
        }
    }
    return result;
}

function normalizeModifiers(values) {
    var present = {};
    for (var index = 0; index < values.length; index += 1) {
        var canonical = modifierAlias(values[index]);
        if (canonical)
            present[canonical] = true;
    }
    return MODIFIER_ORDER.filter(function(name) { return present[name] === true; });
}

function physicalCode(value) {
    var candidate = value;
    if (typeof candidate === "string") {
        var codeMatch = /^code\s*:\s*(\d+)$/i.exec(trimmed(candidate));
        if (codeMatch)
            candidate = codeMatch[1];
    }
    var number = Number(candidate);
    if (!isFinite(number) || Math.floor(number) !== number || number < 1 || number > 767)
        return 0;
    return number;
}

function shortcutCode(value) {
    if (!isObject(value))
        return 0;
    var candidates = ["code", "keycode", "scanCode", "nativeScanCode"];
    for (var index = 0; index < candidates.length; index += 1) {
        if (own(value, candidates[index])) {
            var explicitCode = physicalCode(value[candidates[index]]);
            if (explicitCode)
                return explicitCode;
        }
    }
    if (typeof value.key === "string") {
        var chordCode = /(?:^|\+)\s*code\s*:\s*(\d+)\s*(?:$|\+)/i.exec(value.key);
        if (chordCode)
            return physicalCode(chordCode[1]);
    }
    return physicalCode(value.key);
}

function shortcutKey(value, code) {
    if (!isObject(value))
        return "";
    var candidate = value.keyName || value.readableKey || value.label || value.key || "";
    candidate = cleanText(candidate, 64);
    if (/(?:^|\+)\s*code\s*:\s*\d+\s*(?:$|\+)/i.test(candidate))
        candidate = "";
    return candidate || (code ? "Key " + code : "");
}

function normalizeShortcut(value) {
    if (!isObject(value))
        return null;
    var code = shortcutCode(value);
    var key = shortcutKey(value, code);
    if (!code || !key)
        return null;
    return {
        modifiers: normalizeModifiers(shortcutModifierInput(value)),
        key: key,
        code: code
    };
}

function isModifierKey(key) {
    var value = trimmed(key).toUpperCase().replace(/[ _-]+/g, "");
    return /^(SHIFT|SHIFTL|SHIFTR|CTRL|CONTROL|CONTROLL|CONTROLR|ALT|ALTL|ALTR|SUPER|SUPERL|SUPERR|META|METAL|METAR|LOGO|HYPER|CAPSLOCK|NUMLOCK|MOD[1-5])$/.test(value);
}

function isFunctionOrMediaKey(key) {
    var value = trimmed(key).toUpperCase().replace(/[ _-]+/g, "");
    if (/^F(?:[1-9]|[12][0-9]|3[0-5])$/.test(value))
        return true;
    if (/^(XF86)?(?:AUDIO|MEDIA|VOLUME|MONBRIGHTNESS|KBDBRIGHTNESS|BRIGHTNESS|PLAY|PAUSE|NEXT|PREV|STOP|MUTE|MICMUTE|CALCULATOR|MAIL|WWW|SEARCH|LAUNCH|POWER|SLEEP|WAKE)/.test(value))
        return true;
    return /^(PRINT|PRINTSCREEN|PAUSE|SCROLLLOCK)$/.test(value);
}

function validateShortcut(value) {
    if (!isObject(value))
        return "Choose a shortcut.";

    var rawModifiers = shortcutModifierInput(value);
    for (var index = 0; index < rawModifiers.length; index += 1) {
        if (!modifierAlias(rawModifiers[index]))
            return "Unknown modifier: " + cleanText(rawModifiers[index], 32) + ".";
    }

    var code = shortcutCode(value);
    var key = shortcutKey(value, code);
    if (!key)
        return "Choose a key.";
    if (isModifierKey(key))
        return "Modifier-only shortcuts are not supported.";
    if (!code)
        return "A physical keycode is required.";

    var modifiers = normalizeModifiers(rawModifiers);
    if (modifiers.length === 0 && !isFunctionOrMediaKey(key))
        return "Add a modifier, or choose a function or media key.";
    return "";
}

function shortcutIdentity(value) {
    var normalized = normalizeShortcut(value);
    if (!normalized)
        return "";
    return normalized.modifiers.join("+") + "|code:" + normalized.code;
}

function shortcutsConflict(shortcut, binding) {
    if (!isObject(shortcut) || !isObject(binding))
        return false;
    var firstModifiers = normalizeModifiers(shortcutModifierInput(shortcut)).join("+");
    var secondModifiers = normalizeModifiers(shortcutModifierInput(binding)).join("+");
    if (firstModifiers !== secondModifiers)
        return false;

    var firstCode = shortcutCode(shortcut);
    var secondCode = shortcutCode(binding);
    if (firstCode && secondCode)
        return firstCode === secondCode;

    function symbolicKey(value) {
        var key = cleanText(value.keyName || value.readableKey || value.label || value.key, 64);
        var pieces = key.split("+");
        for (var index = pieces.length - 1; index >= 0; index -= 1) {
            var piece = trimmed(pieces[index]);
            if (!piece || modifierAlias(piece) || /^code\s*:/i.test(piece))
                continue;
            var normalized = piece.toUpperCase().replace(/[^A-Z0-9]/g, "");
            var aliases = {
                ENTER: "RETURN",
                KPENTER: "RETURN",
                BACKTAB: "TAB",
                ISOLEFTTAB: "TAB",
                VOLUMEUP: "AUDIOVOLUMEUP",
                XF86AUDIORAISEVOLUME: "AUDIOVOLUMEUP",
                VOLUMEDOWN: "AUDIOVOLUMEDOWN",
                XF86AUDIOLOWERVOLUME: "AUDIOVOLUMEDOWN",
                VOLUMEMUTE: "AUDIOVOLUMEMUTE",
                XF86AUDIOMUTE: "AUDIOVOLUMEMUTE",
                MEDIAPLAY: "AUDIOPLAY",
                XF86AUDIOPLAY: "AUDIOPLAY",
                MEDIAPAUSE: "AUDIOPAUSE",
                XF86AUDIOPAUSE: "AUDIOPAUSE",
                MEDIASTOP: "AUDIOSTOP",
                XF86AUDIOSTOP: "AUDIOSTOP",
                MEDIAPREVIOUS: "AUDIOPREV",
                XF86AUDIOPREV: "AUDIOPREV",
                MEDIANEXT: "AUDIONEXT",
                XF86AUDIONEXT: "AUDIONEXT",
                MONBRIGHTNESSUP: "MONBRIGHTNESSUP",
                XF86MONBRIGHTNESSUP: "MONBRIGHTNESSUP",
                MONBRIGHTNESSDOWN: "MONBRIGHTNESSDOWN",
                XF86MONBRIGHTNESSDOWN: "MONBRIGHTNESSDOWN",
                KBDBRIGHTNESSUP: "KBDBRIGHTNESSUP",
                XF86KBDBRIGHTNESSUP: "KBDBRIGHTNESSUP",
                KBDBRIGHTNESSDOWN: "KBDBRIGHTNESSDOWN",
                XF86KBDBRIGHTNESSDOWN: "KBDBRIGHTNESSDOWN"
            };
            return aliases[normalized] || normalized;
        }
        return "";
    }

    var firstKey = symbolicKey(shortcut);
    var secondKey = symbolicKey(binding);
    return firstKey !== "" && secondKey !== "" && firstKey === secondKey;
}

function parseHyprctlBindsText(text) {
    var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n");
    var bindings = [];
    var current = null;

    function freshBinding(type) {
        return {
            type: type,
            modmask: 0,
            submap: "",
            key: "",
            keycode: 0,
            description: "",
            dispatcher: "",
            arg: ""
        };
    }

    function finish() {
        if (!current)
            return;
        // A malformed diagnostic block without a key is not a binding.
        if (current.key || current.keycode)
            bindings.push(current);
        current = null;
    }

    for (var index = 0; index < lines.length; index += 1) {
        var line = lines[index];
        var header = /^\s*(bind[a-z]*)\s*:?[ \t]*$/i.exec(line);
        if (header) {
            finish();
            current = freshBinding(header[1].toLowerCase());
            continue;
        }
        if (!current)
            continue;

        var field = /^\s*([A-Za-z_][A-Za-z0-9_]*):[ \t]*(.*)$/.exec(line);
        if (!field)
            continue;
        var name = field[1].toLowerCase();
        var value = field[2].replace(/[ \t]+$/g, "");
        if (name === "modmask") {
            var mask = Number(value);
            current.modmask = isFinite(mask) && mask >= 0 ? Math.floor(mask) : 0;
        } else if (name === "keycode") {
            current.keycode = physicalCode(value);
        } else if (name === "submap" || name === "key" || name === "description" || name === "dispatcher" || name === "arg") {
            // Do not tokenize key here: preserving the exact text is the point
            // of this parser and lets conflict detection recover code:N.
            current[name] = value;
        }
    }
    finish();
    return bindings;
}

function luaQuote(value) {
    var source = String(value === null || value === undefined ? "" : value);
    var result = "\"";
    for (var index = 0; index < source.length; index += 1) {
        var code = source.charCodeAt(index);
        var character = source.charAt(index);
        if (character === "\\")
            result += "\\\\";
        else if (character === "\"")
            result += "\\\"";
        else if (character === "\n")
            result += "\\n";
        else if (character === "\r")
            result += "\\r";
        else if (character === "\t")
            result += "\\t";
        else if (character === "\b")
            result += "\\b";
        else if (character === "\f")
            result += "\\f";
        else if (code < 32 || code === 127)
            result += "\\" + ("00" + code).slice(-3);
        else
            result += character;
    }
    return result + "\"";
}

function defaultSettings() {
    return {
        layouts: [],
        displayMode: "both",
        osdEnabled: false,
        shortcut: null,
        layoutScope: "global",
        applicationLayouts: {},
        deviceOverrides: {},
        adoptedExistingConfig: false,
        nativeXkbOption: ""
    };
}

function normalizeApplicationId(value) {
    var result = cleanText(value, 256).toLowerCase();
    if (!result || result === "__proto__" || result === "prototype" || result === "constructor")
        return "";
    return result;
}

function normalizeWindowAddress(value) {
    var match = /^(?:0x)?([0-9a-f]{1,16})$/i.exec(trimmed(value));
    if (!match)
        return "";
    var address = match[1].toLowerCase().replace(/^0+/, "");
    return address ? "0x" + address : "";
}

function sanitizeLayoutMemories(value, layouts) {
    var result = {};
    if (!isObject(value))
        return result;
    var validLayouts = {};
    var sourceLayouts = Array.isArray(layouts) ? layouts : [];
    for (var layoutIndex = 0; layoutIndex < sourceLayouts.length; layoutIndex += 1) {
        var key = layoutKey(sourceLayouts[layoutIndex]);
        if (key)
            validLayouts["$" + key] = true;
    }
    var keys = Object.keys(value).slice(0, 128);
    for (var index = 0; index < keys.length; index += 1) {
        var identity = normalizeApplicationId(keys[index]);
        var remembered = String(value[keys[index]] || "");
        if (identity && validLayouts["$" + remembered])
            result[identity] = remembered;
    }
    return result;
}

function sanitizeApplicationLayouts(value, layouts) {
    return sanitizeLayoutMemories(value, layouts);
}

function rememberedLayoutIndex(value, identity, layouts) {
    var normalizedIdentity = normalizeApplicationId(identity);
    if (!normalizedIdentity || !isObject(value))
        return -1;
    var remembered = String(value[normalizedIdentity] || "");
    var sourceLayouts = Array.isArray(layouts) ? layouts : [];
    for (var index = 0; index < sourceLayouts.length; index += 1) {
        if (layoutKey(sourceLayouts[index]) === remembered)
            return index;
    }
    return -1;
}

function applicationLayoutIndex(value, applicationId, layouts) {
    return rememberedLayoutIndex(value, applicationId, layouts);
}

function sanitizeNativeXkbOption(value) {
    var option = cleanText(value, 128);
    return nativeXkbShortcutOptions().some(function(entry) { return entry.value === option; })
        ? option : "";
}

function nativeXkbShortcutOptions() {
    return [
        { value: "grp:toggle", label: "Right Alt" },
        { value: "grp:lalt_toggle", label: "Left Alt" },
        { value: "grp:alt_shift_toggle", label: "Alt + Shift", capture: ["ALT", "SHIFT"] },
        { value: "grp:lalt_lshift_toggle", label: "Left Alt + Left Shift" },
        { value: "grp:ralt_rshift_toggle", label: "Right Alt + Right Shift" },
        { value: "grp:alt_shift_toggle_bidir", label: "Alt + Shift · directional" },
        { value: "grp:ctrl_shift_toggle", label: "Ctrl + Shift", capture: ["CTRL", "SHIFT"] },
        { value: "grp:lctrl_lshift_toggle", label: "Left Ctrl + Left Shift" },
        { value: "grp:rctrl_rshift_toggle", label: "Right Ctrl + Right Shift" },
        { value: "grp:ctrl_shift_toggle_bidir", label: "Ctrl + Shift · directional" },
        { value: "grp:ctrl_alt_toggle", label: "Ctrl + Alt", capture: ["CTRL", "ALT"] },
        { value: "grp:lctrl_lalt_toggle", label: "Left Ctrl + Left Alt" },
        { value: "grp:rctrl_ralt_toggle", label: "Right Ctrl + Right Alt" },
        { value: "grp:ctrl_alt_toggle_bidir", label: "Ctrl + Alt · directional" },
        { value: "grp:win_space_toggle", label: "Super + Space", capture: ["SUPER", "SPACE"] },
        { value: "grp:alt_space_toggle", label: "Alt + Space", capture: ["ALT", "SPACE"] },
        { value: "grp:ctrl_space_toggle", label: "Ctrl + Space", capture: ["CTRL", "SPACE"] },
        { value: "grp:caps_toggle", label: "Caps Lock", capture: ["CAPSLOCK"] },
        { value: "grp:shift_caps_toggle", label: "Shift + Caps Lock", capture: ["SHIFT", "CAPSLOCK"] },
        { value: "grp:alt_caps_toggle", label: "Alt + Caps Lock", capture: ["ALT", "CAPSLOCK"] },
        { value: "grp:shifts_toggle", label: "Both Shift keys" },
        { value: "grp:alts_toggle", label: "Both Alt keys" },
        { value: "grp:alt_altgr_toggle", label: "Both Alt keys · preserve AltGr" },
        { value: "grp:ctrls_toggle", label: "Both Ctrl keys" },
        { value: "grp:menu_toggle", label: "Menu", capture: ["MENU"] },
        { value: "grp:lwin_toggle", label: "Left Super" },
        { value: "grp:rwin_toggle", label: "Right Super" },
        { value: "grp:lshift_toggle", label: "Left Shift" },
        { value: "grp:rshift_toggle", label: "Right Shift" },
        { value: "grp:lctrl_toggle", label: "Left Ctrl" },
        { value: "grp:rctrl_toggle", label: "Right Ctrl" },
        { value: "grp:sclk_toggle", label: "Scroll Lock", capture: ["SCROLLLOCK"] },
        { value: "grp:lctrl_lwin_toggle", label: "Left Ctrl + Left Super" }
    ];
}

function nativeXkbOptionForChord(parts) {
    var order = ["SUPER", "CTRL", "ALT", "SHIFT", "SPACE", "CAPSLOCK", "MENU", "SCROLLLOCK"];
    var seen = {};
    var normalized = [];
    (Array.isArray(parts) ? parts : []).forEach(function(part) {
        var value = String(part || "").trim().toUpperCase().replace(/[ _-]/g, "");
        if (order.indexOf(value) === -1 || seen[value]) return;
        seen[value] = true;
        normalized.push(value);
    });
    normalized.sort(function(left, right) { return order.indexOf(left) - order.indexOf(right); });
    var signature = normalized.join("+");
    var options = nativeXkbShortcutOptions();
    for (var index = 0; index < options.length; index += 1) {
        var capture = Array.isArray(options[index].capture) ? options[index].capture.slice() : [];
        capture.sort(function(left, right) { return order.indexOf(left) - order.indexOf(right); });
        if (capture.length > 0 && capture.join("+") === signature)
            return options[index].value;
    }
    return "";
}

function withoutGroupToggle(value) {
    return String(value || "").split(",").map(trimmed).filter(function(option) {
        return option && !/^grp:[a-z0-9_]+$/i.test(option);
    }).join(",");
}

function withGroupToggle(value, option) {
    var base = withoutGroupToggle(value);
    var group = sanitizeNativeXkbOption(option);
    return [base, group].filter(function(part) { return part !== ""; }).join(",");
}

function nativeXkbShortcutLabel(value) {
    var option = sanitizeNativeXkbOption(value);
    var options = nativeXkbShortcutOptions();
    for (var index = 0; index < options.length; index += 1) {
        if (options[index].value === option)
            return options[index].label;
    }
    return "";
}

function parseHyprOptionString(text) {
    try {
        var parsed = JSON.parse(String(text || ""));
        return cleanText(parsed && parsed.str, 512);
    } catch (error) {
        return "";
    }
}

function firstGroupToggle(value) {
    var options = String(value || "").split(",");
    for (var index = 0; index < options.length; index += 1) {
        var option = sanitizeNativeXkbOption(options[index]);
        if (option)
            return option;
    }
    return "";
}

function sanitizeOverrides(value) {
    var result = {};
    if (!isObject(value))
        return result;
    var keys = Object.keys(value);
    for (var index = 0; index < keys.length; index += 1) {
        var key = cleanText(keys[index], 512);
        if (!key || key === "__proto__" || key === "prototype" || key === "constructor")
            continue;
        var policy = typeof value[keys[index]] === "string" ? value[keys[index]].toLowerCase() : "";
        if (policy === "manage" || policy === "ignore")
            result[key] = policy;
    }
    return result;
}

function sanitizeSettings(value) {
    var source = isObject(value) ? value : {};
    var result = defaultSettings();
    result.layouts = uniqueLayouts(source.layouts);
    if (DISPLAY_MODES.indexOf(source.displayMode) >= 0)
        result.displayMode = source.displayMode;
    result.osdEnabled = source.osdEnabled === true;
    if (source.shortcut && validateShortcut(source.shortcut) === "")
        result.shortcut = normalizeShortcut(source.shortcut);
    var layoutScope = source.layoutScope;
    if (LAYOUT_SCOPES.indexOf(layoutScope) < 0) {
        if (source.applicationMode === "remember")
            layoutScope = "application";
        else if (source.applicationMode === "window")
            layoutScope = "window";
    }
    if (LAYOUT_SCOPES.indexOf(layoutScope) >= 0)
        result.layoutScope = layoutScope;
    result.applicationLayouts = sanitizeApplicationLayouts(source.applicationLayouts, result.layouts);
    result.deviceOverrides = sanitizeOverrides(source.deviceOverrides);
    result.adoptedExistingConfig = source.adoptedExistingConfig === true;
    result.nativeXkbOption = result.shortcut ? "" : sanitizeNativeXkbOption(source.nativeXkbOption);
    return result;
}

function unescapeProcName(value) {
    return String(value || "").replace(/\\\"/g, "\"").replace(/\\\\/g, "\\");
}

function parseProcInputDevices(text) {
    var blocks = String(text || "").replace(/\r\n?/g, "\n").split(/\n\s*\n/);
    var devices = [];
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex += 1) {
        var block = trimmed(blocks[blockIndex]);
        if (!block)
            continue;

        var device = {
            bus: "",
            vendor: "",
            product: "",
            version: "",
            vendorId: "",
            productId: "",
            name: "",
            phys: "",
            sysfs: "",
            uniq: "",
            handlers: [],
            capabilities: {}
        };
        var lines = block.split("\n");
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
            var line = lines[lineIndex];
            var identity = /^I:\s*Bus=([0-9A-Fa-f]+)\s+Vendor=([0-9A-Fa-f]+)\s+Product=([0-9A-Fa-f]+)\s+Version=([0-9A-Fa-f]+)/.exec(line);
            if (identity) {
                device.bus = identity[1].toLowerCase();
                device.vendor = identity[2].toLowerCase();
                device.product = identity[3].toLowerCase();
                device.version = identity[4].toLowerCase();
                device.vendorId = device.vendor;
                device.productId = device.product;
                continue;
            }
            var name = /^N:\s*Name="(.*)"\s*$/.exec(line);
            if (name) {
                device.name = unescapeProcName(name[1]);
                continue;
            }
            var phys = /^P:\s*Phys=(.*)$/.exec(line);
            if (phys) {
                device.phys = trimmed(phys[1]);
                continue;
            }
            var sysfs = /^S:\s*Sysfs=(.*)$/.exec(line);
            if (sysfs) {
                device.sysfs = trimmed(sysfs[1]);
                continue;
            }
            var uniq = /^U:\s*Uniq=(.*)$/.exec(line);
            if (uniq) {
                device.uniq = trimmed(uniq[1]);
                continue;
            }
            var handlers = /^H:\s*Handlers=(.*)$/.exec(line);
            if (handlers) {
                device.handlers = trimmed(handlers[1]).split(/\s+/).filter(function(handler) { return handler !== ""; });
                continue;
            }
            var capability = /^B:\s*([A-Za-z0-9_]+)=(.*)$/.exec(line);
            if (capability)
                device.capabilities[capability[1]] = trimmed(capability[2]);
        }
        device.bitmaps = device.capabilities;
        devices.push(device);
    }
    return devices;
}

function normalizeDeviceName(value) {
    return cleanText(value, 256).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function matchInputDevice(hyprlandName, parsedProcDevices) {
    var runtimeName = isObject(hyprlandName) ? hyprlandName.name : hyprlandName;
    var wanted = normalizeDeviceName(runtimeName);
    if (!wanted || !Array.isArray(parsedProcDevices))
        return null;

    var matches = [];
    for (var index = 0; index < parsedProcDevices.length; index += 1) {
        if (normalizeDeviceName(parsedProcDevices[index].name) === wanted)
            matches.push(parsedProcDevices[index]);
    }
    return matches.length === 1 ? matches[0] : null;
}

function normalizeHexId(value) {
    var result = trimmed(value).toLowerCase().replace(/^0x/, "");
    if (!/^[0-9a-f]+$/.test(result))
        return "";
    return ("0000" + result).slice(-4);
}

function fingerprintPart(value) {
    return encodeURIComponent(cleanText(value, 512).toLowerCase());
}

function stableDeviceFingerprint(input, keyboard) {
    var device = isObject(input) ? input : {};
    var runtime = isObject(keyboard) ? keyboard : {};
    var vendor = normalizeHexId(device.vendor || device.vendorId || runtime.vendor || runtime.vendorId);
    var product = normalizeHexId(device.product || device.productId || runtime.product || runtime.productId);
    var serial = cleanText(device.uniq || device.serial || runtime.serial, 256);
    var physical = cleanText(device.phys || device.physical || runtime.phys || runtime.physical, 512);
    if (!vendor || !product || (!serial && !physical))
        return "";

    var identityType = serial ? "serial" : "phys";
    var identity = serial || physical;
    var role = normalizeDeviceName(device.name || runtime.description || runtime.name);
    var fingerprint = "v1:" + vendor + ":" + product + ":" + identityType + ":" + fingerprintPart(identity);
    // A composite HID can expose a typing keyboard, consumer control, system
    // control and pointer under one serial. The stable role suffix prevents a
    // user override for one interface from leaking to the others.
    if (role)
        fingerprint += ":role:" + fingerprintPart(role);
    return fingerprint;
}

function hasHandler(device, pattern) {
    var handlers = device && Array.isArray(device.handlers) ? device.handlers : [];
    for (var index = 0; index < handlers.length; index += 1) {
        if (pattern.test(handlers[index]))
            return true;
    }
    return false;
}

function capabilitySize(device, name) {
    var value = device && device.capabilities ? device.capabilities[name] : "";
    return String(value || "").replace(/[^0-9a-f]/gi, "").length;
}

function baseDeviceAssessment(keyboard, input) {
    if (!input) {
        return {
            managed: false,
            security: false,
            ambiguous: true,
            category: "ambiguous",
            reason: "No unique kernel input device matches this compositor device."
        };
    }

    var runtimeName = isObject(keyboard) ? (keyboard.name || keyboard.description || "") : String(keyboard || "");
    var haystack = [input.name, runtimeName, input.phys, input.sysfs].join(" ");
    var vendor = normalizeHexId(input.vendor || input.vendorId);
    var securityName = /\b(?:yubico|yubikey|fido2?|u2f|otp|ccid|nitrokey|solokey|onlykey|security\s*(?:key|token)|authentication\s*(?:key|token)|smart\s*card)\b/i.test(haystack);
    if (securityName || vendor === "1050" || (vendor === "20a0" && /nitro/i.test(haystack))) {
        return {
            managed: false,
            security: true,
            ambiguous: false,
            category: "security",
            reason: "Security tokens and authentication devices are ignored."
        };
    }

    if (input.bus === "0006" || /\b(?:virtual|uinput|ydotool|wtype|dotool|keyd|emulated|dummy)\b/i.test(haystack)) {
        return {
            managed: false,
            security: false,
            ambiguous: false,
            category: "virtual",
            reason: "Virtual and synthetic input devices are ignored."
        };
    }

    if (/\b(?:(?:power|sleep|lid)\s+button|system\s+control|consumer\s+control|video\s+bus|pc\s+speaker|hotkeys?|extra\s+buttons?)\b/i.test(haystack)) {
        return {
            managed: false,
            security: false,
            ambiguous: false,
            category: "control",
            reason: "Button, system-control and consumer-control interfaces are ignored."
        };
    }

    var pointerName = /\b(?:mouse|touchpad|trackpoint|trackball|pointer|tablet|joystick|gamepad)\b/i.test(haystack);
    var pointerHandler = hasHandler(input, /^(?:mouse|js)\d+$/);
    if (pointerName || pointerHandler) {
        return {
            managed: false,
            security: false,
            ambiguous: false,
            category: "pointer",
            reason: "Pointer and mixed pointer interfaces are ignored."
        };
    }

    if (!hasHandler(input, /^kbd$/)) {
        return {
            managed: false,
            security: false,
            ambiguous: false,
            category: "non-keyboard",
            reason: "The kernel does not expose this interface as a keyboard."
        };
    }

    var fingerprint = stableDeviceFingerprint(input, keyboard);
    var nonZeroIds = normalizeHexId(input.vendor || input.vendorId) !== "0000" && normalizeHexId(input.product || input.productId) !== "0000";
    var fullTypingCapabilities = hasHandler(input, /^sysrq$/) && hasHandler(input, /^leds$/) && capabilitySize(input, "KEY") >= 48;
    if (!fingerprint || !nonZeroIds || !fullTypingCapabilities) {
        return {
            managed: false,
            security: false,
            ambiguous: true,
            category: "ambiguous",
            reason: "This keyboard-like interface cannot be identified as a typing keyboard with high confidence."
        };
    }

    return {
        managed: true,
        security: false,
        ambiguous: false,
        category: "keyboard",
        reason: "High-confidence typing keyboard."
    };
}

function overridePolicy(value) {
    if (value === false)
        return "ignore";
    if (value === true)
        return "manage";
    if (typeof value === "string") {
        var text = value.toLowerCase();
        if (text === "ignore" || text === "manage")
            return text;
    }
    if (isObject(value)) {
        if (value.ignore === true || value.policy === "ignore" || value.action === "ignore")
            return "ignore";
        if (value.manage === true || value.policy === "manage" || value.action === "manage")
            return "manage";
    }
    return "";
}

function classifyDevice(keyboard, input, override) {
    // The one-argument form is convenient for tests and callers that only have
    // a /proc record. The public service uses all three arguments.
    if (input === undefined && isObject(keyboard) && Array.isArray(keyboard.handlers)) {
        input = keyboard;
        keyboard = null;
    }

    var assessment = baseDeviceAssessment(keyboard, input);
    var policy = overridePolicy(override);
    var runtimeName = isObject(keyboard) ? (keyboard.name || "") : String(keyboard || "");
    var result = {
        runtimeName: runtimeName,
        fingerprint: stableDeviceFingerprint(input, keyboard),
        label: input && input.name ? input.name : runtimeName,
        managed: assessment.managed,
        security: assessment.security,
        ambiguous: assessment.ambiguous,
        category: assessment.category,
        reason: assessment.reason,
        source: "automatic",
        requiresConfirmation: false
    };

    // Ignore intentionally wins if a malformed override object contains both
    // policies. This keeps the precedence deterministic and fail-closed.
    if (policy === "ignore") {
        result.managed = false;
        result.source = "override";
        result.reason = "Explicitly ignored by the user.";
    } else if (policy === "manage") {
        result.managed = true;
        result.source = "override";
        result.requiresConfirmation = assessment.security || assessment.ambiguous || assessment.category !== "keyboard";
        result.reason = result.requiresConfirmation
            ? "Explicitly managed despite the device safety classification."
            : "Explicitly managed by the user.";
    }
    return result;
}

var exported = {
    DISPLAY_MODES: DISPLAY_MODES,
    LAYOUT_SCOPES: LAYOUT_SCOPES,
    defaultSettings: defaultSettings,
    sanitizeSettings: sanitizeSettings,
    parseXkbCatalog: parseXkbCatalog,
    normalizeLayoutEntry: normalizeLayoutEntry,
    uniqueLayouts: uniqueLayouts,
    layoutKey: layoutKey,
    regionalFlag: regionalFlag,
    inferFlag: inferFlag,
    displayForLayout: displayForLayout,
    luaQuote: luaQuote,
    normalizeShortcut: normalizeShortcut,
    validateShortcut: validateShortcut,
    shortcutIdentity: shortcutIdentity,
    shortcutsConflict: shortcutsConflict,
    parseHyprctlBindsText: parseHyprctlBindsText,
    parseProcInputDevices: parseProcInputDevices,
    normalizeDeviceName: normalizeDeviceName,
    matchInputDevice: matchInputDevice,
    stableDeviceFingerprint: stableDeviceFingerprint,
    classifyDevice: classifyDevice,
    parseHyprOptionString: parseHyprOptionString,
    firstGroupToggle: firstGroupToggle,
    nativeXkbShortcutOptions: nativeXkbShortcutOptions,
    nativeXkbOptionForChord: nativeXkbOptionForChord,
    withoutGroupToggle: withoutGroupToggle,
    withGroupToggle: withGroupToggle,
    nativeXkbShortcutLabel: nativeXkbShortcutLabel,
    normalizeApplicationId: normalizeApplicationId,
    normalizeWindowAddress: normalizeWindowAddress,
    sanitizeLayoutMemories: sanitizeLayoutMemories,
    sanitizeApplicationLayouts: sanitizeApplicationLayouts,
    rememberedLayoutIndex: rememberedLayoutIndex,
    applicationLayoutIndex: applicationLayoutIndex
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
