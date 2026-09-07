// Cheap drift guards on manifest.json: it is the contract the shell's
// PluginRegistry and omarchy-plugin-validate both enforce, and a typo in it
// fails at shell-load time rather than anywhere a unit test would look.
const { readFileSync, existsSync, readdirSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const root = join(__dirname, "..");
const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"));

test("the manifest carries every field the registry requires", () => {
    assert.equal(manifest.schemaVersion, 1);
    for (const key of ["id", "name", "version", "author", "description", "kinds", "entryPoints"]) {
        assert.ok(manifest[key], `missing ${key}`);
    }
    assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/);
    // omarchy.* is reserved for first-party plugins.
    assert.ok(!manifest.id.startsWith("omarchy."));
    assert.ok(Array.isArray(manifest.kinds) && manifest.kinds.length > 0);
});

test("every declared kind has an entry point that exists on disk", () => {
    const pairs = { bar: "bar", "bar-widget": "barWidget", menu: "menu", overlay: "overlay", panel: "panel", service: "service" };
    for (const kind of manifest.kinds) {
        const key = pairs[kind];
        assert.ok(key, `unknown kind ${kind}`);
        const entry = manifest.entryPoints[key];
        assert.ok(entry, `kind ${kind} needs entryPoints.${key}`);
        assert.ok(!entry.includes(".."), "entry points must not escape the plugin folder");
        assert.ok(existsSync(join(root, entry)), `${entry} does not exist`);
    }
});

test("Panel.qml is loaded by the widget, never declared as an entry point", () => {
    // Declaring it would make the shell mount a second, unanchored copy.
    for (const value of Object.values(manifest.entryPoints)) {
        assert.notEqual(value, "Panel.qml");
    }
    assert.match(readFileSync(join(root, "BarWidget.qml"), "utf8"), /Qt\.resolvedUrl\("Panel\.qml"\)/);
});

test("the bar widget block uses only settings types the shell renders", () => {
    const widget = manifest.barWidget;
    assert.ok(["left", "center", "right"].includes(widget.defaultSection));

    const renderable = new Set(["integer", "string", "boolean", "enum", "path", "multiselect"]);
    const schemaKeys = new Set();
    for (const field of widget.schema) {
        assert.ok(renderable.has(field.type), `unrenderable settings type: ${field.type}`);
        if (field.type === "enum") assert.ok(Array.isArray(field.options) && field.options.length > 0);
        schemaKeys.add(field.key);
    }

    // Anything in defaults{} that the schema does not describe is invisible in
    // the settings dialog and would be dropped by a settings write-back.
    for (const key of Object.keys(widget.defaults)) {
        assert.ok(schemaKeys.has(key), `defaults.${key} has no schema entry`);
    }
});

test("vault configuration is deliberately kept out of the widget settings schema", () => {
    // updateEntryInline replaces the whole layout entry and the schema has no
    // list type, so vault paths, pins and recent queries live in the state
    // file instead. See README "Where state lives".
    const Model = require(join(root, "Model.js"));
    const schemaKeys = manifest.barWidget.schema.map(f => f.key);
    for (const key of Object.keys(Model.DEFAULT_CONFIG)) {
        assert.ok(!schemaKeys.includes(key), `${key} must not be a widget setting`);
    }
});

test("every local QML file the panel loads is present", () => {
    const referenced = new Set();
    for (const file of readdirSync(root).filter(name => name.endsWith(".qml"))) {
        const source = readFileSync(join(root, file), "utf8");
        for (const match of source.matchAll(/Qt\.resolvedUrl\("([^"]+)"\)/g)) referenced.add(match[1]);
        // Locally-defined components are used bare, so pick them up by name.
        for (const match of source.matchAll(/^\s{2,}([A-Z][A-Za-z]+)\s*\{/gm)) {
            const name = match[1] + ".qml";
            if (existsSync(join(root, name))) referenced.add(name);
        }
    }
    for (const name of referenced) {
        assert.ok(existsSync(join(root, name)), `${name} is referenced but missing`);
    }
    assert.ok(referenced.has("Panel.qml"));
    assert.ok(referenced.has("CaptureView.qml"));
});
