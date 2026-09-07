// Clipboard contents, page names, window titles and search hits all render
// straight into Text{}, so every local sink must be explicitly PlainText --
// a copied string like "<img src=x onerror=…>" would otherwise be live markup.
// Scoped to each Text{}'s own brace-matched body, since id/anchors routinely
// precede the text/textFormat lines.
const { readFileSync, readdirSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

test("every local QML Text sink is explicitly plain text", () => {
    const root = join(__dirname, "..");
    for (const file of readdirSync(root).filter(name => name.endsWith(".qml"))) {
        const lines = readFileSync(join(root, file), "utf8").split("\n");
        for (let i = 0; i < lines.length; i++) {
            if (!/\bText\s*\{/.test(lines[i])) continue;
            const openIdx = lines[i].indexOf("{");
            let depth = 0;
            for (let c = openIdx; c < lines[i].length; c++) {
                if (lines[i][c] === "{") depth++;
                else if (lines[i][c] === "}") depth--;
            }
            const body = [];
            let j = i + 1;
            while (depth > 0 && j < lines.length) {
                body.push(lines[j]);
                for (let c = 0; c < lines[j].length; c++) {
                    if (lines[j][c] === "{") depth++;
                    else if (lines[j][c] === "}") depth--;
                }
                j++;
            }
            assert.match(body.join("\n"), /textFormat:\s*Text\.PlainText/, `${file}:${i + 1}`);
        }
    }
});
