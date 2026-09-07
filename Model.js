// Model.js -- every pure function in ObsNote. No QML types, so QML
// (`import "Model.js" as Model`) and `node --test` load this exact file.
// ES5 style throughout so both engines agree.

// ---------------------------------------------------------------- config ----

var STORE_VERSION = 1

var DEFAULT_CONFIG = {
  vaultPath: "",              // absolute path to the Obsidian vault root
  vaultName: "",              // vault name as Obsidian knows it (obsidian:// URIs)
  folder: "Scratchpad",       // vault-relative folder that holds capture pages
  defaultPage: "Inbox",       // page used by quick capture
  attachments: "Attachments", // subfolder of `folder` for pasted images
  indexPage: "",              // vault-relative markdown file to link the folder from
  includeSource: true,        // stamp app / window title / URL onto each capture
  autoFence: true,            // wrap command- and code-looking text in a fence
  timestampHeadings: true,    // each capture gets its own `## ` heading
  notify: true                // omarchy-notification-send on capture
}

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

function str(v, fallback) {
  if (v === undefined || v === null) return fallback
  return String(v)
}

function bool(v, fallback) {
  if (v === true || v === false) return v
  if (v === "true") return true
  if (v === "false") return false
  return fallback
}

// Total by contract: anything malformed degrades to a default rather than
// throwing inside a QML signal handler.
function normalizeConfig(raw) {
  var src = isObject(raw) ? raw : {}
  var out = {
    vaultPath: cleanPath(str(src.vaultPath, DEFAULT_CONFIG.vaultPath)),
    vaultName: str(src.vaultName, DEFAULT_CONFIG.vaultName).trim(),
    folder: sanitizeFolder(str(src.folder, DEFAULT_CONFIG.folder)),
    defaultPage: sanitizePageName(str(src.defaultPage, DEFAULT_CONFIG.defaultPage)),
    attachments: sanitizeFolder(str(src.attachments, DEFAULT_CONFIG.attachments)),
    indexPage: sanitizeRelative(str(src.indexPage, DEFAULT_CONFIG.indexPage)),
    includeSource: bool(src.includeSource, DEFAULT_CONFIG.includeSource),
    autoFence: bool(src.autoFence, DEFAULT_CONFIG.autoFence),
    timestampHeadings: bool(src.timestampHeadings, DEFAULT_CONFIG.timestampHeadings),
    notify: bool(src.notify, DEFAULT_CONFIG.notify)
  }
  if (!out.folder) out.folder = DEFAULT_CONFIG.folder
  if (!out.defaultPage) out.defaultPage = DEFAULT_CONFIG.defaultPage
  if (!out.attachments) out.attachments = DEFAULT_CONFIG.attachments
  if (!out.vaultName && out.vaultPath) out.vaultName = basename(out.vaultPath)
  return out
}

// A vault is only usable once we know where it is; the panel shows this list
// instead of failing silently on the first capture.
function configIssues(cfg) {
  var c = normalizeConfig(cfg)
  var issues = []
  if (!c.vaultPath) issues.push("No vault selected")
  else if (c.vaultPath.charAt(0) !== "/") issues.push("Vault path must be absolute")
  if (!c.folder) issues.push("No capture folder set")
  if (!c.defaultPage) issues.push("No default page set")
  return issues
}

function configReady(cfg) { return configIssues(cfg).length === 0 }

// ------------------------------------------------------------ path names ----

function cleanPath(p) {
  var s = String(p === undefined || p === null ? "" : p).trim()
  if (!s) return ""
  s = s.replace(/\/+/g, "/")
  if (s.length > 1) s = s.replace(/\/+$/, "")
  return s
}

function basename(p) {
  var s = cleanPath(p)
  if (!s) return ""
  var parts = s.split("/")
  return parts[parts.length - 1] || s
}

// A folder may nest ("Notes/Scratch") but must never escape the vault.
function sanitizeFolder(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw).trim()
  s = s.replace(/\\/g, "/").replace(/\/+/g, "/")
  s = s.replace(/^\/+/, "").replace(/\/+$/, "")
  if (!s) return ""
  var parts = s.split("/")
  var keep = []
  for (var i = 0; i < parts.length; i++) {
    var seg = sanitizeSegment(parts[i])
    if (seg) keep.push(seg)
  }
  return keep.join("/")
}

function sanitizeRelative(raw) {
  var s = sanitizeFolder(String(raw === undefined || raw === null ? "" : raw).replace(/\.md$/i, ""))
  return s ? s + ".md" : ""
}

// One path segment of user text, safe to hand to the filesystem: no control
// characters, no separators, no dot-files, no traversal.
function sanitizeSegment(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw)
  s = s.replace(/[\x00-\x1f\x7f]/g, "")
  s = s.replace(/[\\:*?"<>|#^\[\]]/g, "-")
  s = s.replace(/\s+/g, " ").trim()
  s = s.replace(/^\.+/, "").trim()
  if (s === "" || s === "." || s === "..") return ""
  if (s.length > 100) s = s.substring(0, 100).trim()
  return s
}

// Page names are user text that becomes a filename. One flat segment only.
function sanitizePageName(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw).trim()
  s = s.replace(/\.md$/i, "")
  s = s.replace(/[\/\\]/g, "-")
  return sanitizeSegment(s)
}

function folderPath(cfg) {
  var c = normalizeConfig(cfg)
  if (!c.vaultPath) return ""
  return c.vaultPath + "/" + c.folder
}

function attachmentsPath(cfg) {
  var base = folderPath(cfg)
  if (!base) return ""
  return base + "/" + normalizeConfig(cfg).attachments
}

function pagePath(cfg, name) {
  var base = folderPath(cfg)
  var page = sanitizePageName(name)
  if (!base || !page) return ""
  return base + "/" + page + ".md"
}

// Vault-relative, extension included -- what Obsidian links and URIs want.
function pageRelative(cfg, name) {
  var c = normalizeConfig(cfg)
  var page = sanitizePageName(name)
  if (!page) return ""
  return c.folder + "/" + page + ".md"
}

function indexPath(cfg) {
  var c = normalizeConfig(cfg)
  if (!c.vaultPath || !c.indexPage) return ""
  return c.vaultPath + "/" + c.indexPage
}

// The folder's own note -- ObsNote keeps its page list in sync and the vault
// index links here rather than to a bare folder.
function folderNoteRelative(cfg) {
  var c = normalizeConfig(cfg)
  return c.folder + "/" + basename(c.folder) + ".md"
}

function folderNotePath(cfg) {
  var c = normalizeConfig(cfg)
  if (!c.vaultPath) return ""
  return c.vaultPath + "/" + folderNoteRelative(cfg)
}

function pageNameFromFile(fileName) {
  return sanitizePageName(String(fileName === undefined || fileName === null ? "" : fileName))
}

// The folder note is a page of ObsNote's own making; it never shows up as a
// capture target.
function listablePages(fileNames, cfg) {
  var c = normalizeConfig(cfg)
  var reserved = basename(c.folder).toLowerCase()
  var seen = {}
  var out = []
  var list = Array.isArray(fileNames) ? fileNames : []
  for (var i = 0; i < list.length; i++) {
    var raw = String(list[i] === undefined || list[i] === null ? "" : list[i])
    if (!/\.md$/i.test(raw)) continue
    var name = pageNameFromFile(raw)
    if (!name) continue
    if (name.toLowerCase() === reserved) continue
    var key = name.toLowerCase()
    if (seen[key]) continue
    seen[key] = true
    out.push(name)
  }
  out.sort(function (a, b) {
    var x = a.toLowerCase(), y = b.toLowerCase()
    return x < y ? -1 : (x > y ? 1 : 0)
  })
  return out
}

function obsidianUri(vaultName, relativePath) {
  var vault = String(vaultName === undefined || vaultName === null ? "" : vaultName)
  var file = String(relativePath === undefined || relativePath === null ? "" : relativePath).replace(/\.md$/i, "")
  if (!vault || !file) return ""
  return "obsidian://open?vault=" + encodeURIComponent(vault) + "&file=" + encodeURIComponent(file)
}

// --------------------------------------------------------------- content ----

function pad2(n) { return (n < 10 ? "0" : "") + n }

function safeDate(date) {
  return (date instanceof Date && !isNaN(date.getTime())) ? date : new Date(0)
}

function formatStamp(date) {
  var d = safeDate(date)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function formatIso(date) {
  var d = safeDate(date)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    + "T" + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

function attachmentFileName(date, extension) {
  var d = safeDate(date)
  var ext = String(extension === undefined || extension === null ? "png" : extension).replace(/^\./, "")
  return "obsnote-" + d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate())
    + "-" + pad2(d.getHours()) + pad2(d.getMinutes()) + pad2(d.getSeconds()) + "." + ext
}

var URL_ONLY = /^https?:\/\/[^\s]+$/i
var URL_ANY = /https?:\/\/[^\s<>()"']+/i

var COMMAND_HEADS = [
  "sudo", "npm", "npx", "yarn", "pnpm", "bun", "git", "docker", "podman",
  "kubectl", "systemctl", "journalctl", "curl", "wget", "cd", "ls", "cat",
  "grep", "rg", "fd", "sed", "awk", "make", "cargo", "go", "rustc", "python",
  "python3", "pip", "node", "deno", "bash", "sh", "zsh", "fish", "pacman",
  "yay", "paru", "apt", "dnf", "brew", "ssh", "scp", "rsync", "tar", "chmod",
  "chown", "mkdir", "rm", "cp", "mv", "export", "psql", "mysql", "redis-cli",
  "bundle", "rails", "rake", "omarchy", "hyprctl", "qs"
]

function isCommandLine(line) {
  var s = String(line === undefined || line === null ? "" : line).trim()
  if (!s) return false
  if (/^[$#>%]\s+\S/.test(s)) return true
  var head = s.split(/\s+/)[0]
  for (var i = 0; i < COMMAND_HEADS.length; i++) {
    if (head === COMMAND_HEADS[i]) return true
  }
  return false
}

function isCodeLike(text) {
  var s = String(text === undefined || text === null ? "" : text)
  if (!s.trim()) return false
  var lines = s.replace(/\r/g, "").split("\n")
  var commandLines = 0
  var indented = 0
  var nonEmpty = 0
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line.trim()) continue
    nonEmpty++
    if (isCommandLine(line)) commandLines++
    if (/^(\t|\s{2,})\S/.test(line)) indented++
  }
  if (nonEmpty === 0) return false
  if (commandLines > 0 && commandLines === nonEmpty) return true
  if (nonEmpty > 1 && indented / nonEmpty >= 0.4) return true
  if (nonEmpty > 1 && /[;{}]\s*$/m.test(s) && /[=(){}\[\];]/.test(s)) return true
  return false
}

function looksLikeJson(text) {
  var s = String(text === undefined || text === null ? "" : text).trim()
  if (!/^[\[{]/.test(s)) return false
  try { JSON.parse(s); return true } catch (e) { return false }
}

function guessLanguage(text) {
  var s = String(text === undefined || text === null ? "" : text)
  if (looksLikeJson(s)) return "json"
  var lines = s.replace(/\r/g, "").split("\n")
  var commandLines = 0
  var nonEmpty = 0
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].trim()) continue
    nonEmpty++
    if (isCommandLine(lines[i])) commandLines++
  }
  if (nonEmpty > 0 && commandLines === nonEmpty) return "bash"
  if (/^\s*(def|class|import|from)\s/m.test(s) && /:\s*$/m.test(s)) return "python"
  if (/^\s*(function|const|let|var)\s/m.test(s)) return "javascript"
  return ""
}

// The format the capture view preselects. The user can always override it.
function suggestFormat(text, cfg) {
  var c = normalizeConfig(cfg)
  var s = String(text === undefined || text === null ? "" : text).trim()
  if (!s) return "text"
  if (URL_ONLY.test(s)) return "link"
  if (c.autoFence && isCodeLike(s)) return "code"
  return "text"
}

var FORMATS = ["text", "bullet", "quote", "code", "link"]

function escapeMarkdownLabel(text) {
  return String(text === undefined || text === null ? "" : text).replace(/([\[\]])/g, "\\$1")
}

function prefixLines(text, prefix, emptyPrefix) {
  var lines = String(text === undefined || text === null ? "" : text).replace(/\r/g, "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    out.push(lines[i].trim() ? prefix + lines[i] : (emptyPrefix === undefined ? "" : emptyPrefix))
  }
  return out.join("\n")
}

// A fence has to outlength the longest backtick run it contains, or pasted
// markdown closes it early and the rest of the page renders as code.
function fenceFor(text) {
  var s = String(text === undefined || text === null ? "" : text)
  var longest = 0
  var runs = s.match(/`+/g)
  if (runs) {
    for (var i = 0; i < runs.length; i++) longest = Math.max(longest, runs[i].length)
  }
  var n = Math.max(3, longest + 1)
  var fence = ""
  for (var j = 0; j < n; j++) fence += "`"
  return fence
}

function renderBody(text, format, options) {
  var opts = isObject(options) ? options : {}
  var s = String(text === undefined || text === null ? "" : text).replace(/\r/g, "")
  s = s.replace(/\s+$/, "")
  if (!s) return ""
  if (format === "bullet") return prefixLines(s, "- ", "")
  if (format === "quote") return prefixLines(s, "> ", ">")
  if (format === "code") {
    var fence = fenceFor(s)
    var lang = opts.language === undefined ? guessLanguage(s) : String(opts.language)
    return fence + lang + "\n" + s + "\n" + fence
  }
  if (format === "link") {
    var url = (s.match(URL_ANY) || [s])[0]
    var label = opts.label ? String(opts.label) : url
    return "[" + escapeMarkdownLabel(label) + "](" + url + ")"
  }
  return s
}

function sourceLine(source) {
  if (!isObject(source)) return ""
  var app = str(source.app, "").trim()
  var title = str(source.title, "").trim()
  var url = str(source.url, "").trim()
  var parts = []
  if (app) parts.push(app)
  if (title && title !== app) parts.push(title)
  var label = parts.join(" — ")
  if (url && URL_ANY.test(url)) {
    return label ? "*from [" + escapeMarkdownLabel(label) + "](" + url + ")*" : "*from <" + url + ">*"
  }
  return label ? "*from " + escapeMarkdownLabel(label) + "*" : ""
}

// The exact bytes appended to a page. Always brackets itself with newlines so
// appending to a file whose last line is unterminated still reads correctly.
function renderBlock(options) {
  var opts = isObject(options) ? options : {}
  var cfg = normalizeConfig(opts.config)
  var body = (opts.body !== undefined && opts.body !== null)
    ? String(opts.body)
    : renderBody(opts.text, opts.format || "text", opts)
  var lines = []
  if (cfg.timestampHeadings) lines.push("## " + (opts.stamp ? String(opts.stamp) : formatStamp(opts.date)))
  if (cfg.includeSource) {
    var meta = sourceLine(opts.source)
    if (meta) { lines.push(""); lines.push(meta) }
  }
  if (lines.length) lines.push("")
  lines.push(body)
  return "\n" + lines.join("\n") + "\n"
}

function imageEmbed(cfg, fileName, caption) {
  var c = normalizeConfig(cfg)
  var name = String(fileName === undefined || fileName === null ? "" : fileName)
  if (!name) return ""
  var embed = "![[" + c.folder + "/" + c.attachments + "/" + name + "]]"
  var cap = String(caption === undefined || caption === null ? "" : caption).trim()
  return cap ? embed + "\n\n" + cap : embed
}

function newPageHeader(name, date) {
  var page = sanitizePageName(name)
  return "---\ncreated: " + formatIso(date) + "\ntags:\n  - obsnote\n---\n\n# " + page + "\n"
}

// ---------------------------------------------------------- page reading ----

function stripFrontMatter(text) {
  var s = String(text === undefined || text === null ? "" : text)
  if (s.indexOf("---") !== 0) return s
  var end = s.indexOf("\n---", 3)
  if (end === -1) return s
  var after = s.indexOf("\n", end + 1)
  return after === -1 ? "" : s.substring(after + 1)
}

// Split a page into the capture blocks the browse view lists. Content before
// the first heading becomes an untitled leading block so nothing is hidden.
function parseBlocks(markdown) {
  var text = String(markdown === undefined || markdown === null ? "" : markdown).replace(/\r/g, "")
  var body = stripFrontMatter(text)
  var lines = body.split("\n")
  var blocks = []
  var current = null
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var m = line.match(/^##\s+(.*)$/)
    if (m) {
      if (current) blocks.push(current)
      current = { heading: m[1].trim(), line: i + 1, body: [] }
      continue
    }
    if (/^#\s+/.test(line) && !current) continue
    if (!current) {
      if (!line.trim()) continue
      current = { heading: "", line: i + 1, body: [] }
    }
    current.body.push(line)
  }
  if (current) blocks.push(current)
  var out = []
  for (var j = 0; j < blocks.length; j++) {
    var b = blocks[j]
    var joined = b.body.join("\n").replace(/^\n+/, "").replace(/\s+$/, "")
    if (!b.heading && !joined) continue
    out.push({
      heading: b.heading,
      line: b.line,
      body: joined,
      preview: previewOf(joined || b.heading, 90)
    })
  }
  return out
}

// A capture's copyable payload is the body without ObsNote's own metadata line
// and without the code fence -- what you actually want in the terminal.
function blockCopyText(block) {
  var body = isObject(block)
    ? String(block.body === undefined || block.body === null ? "" : block.body)
    : String(block === undefined || block === null ? "" : block)
  var lines = body.replace(/\r/g, "").split("\n")
  var keep = []
  for (var i = 0; i < lines.length; i++) {
    if (i === 0 && /^\*from .*\*$/.test(lines[i].trim())) continue
    keep.push(lines[i])
  }
  var text = keep.join("\n").replace(/^\n+/, "").replace(/\s+$/, "")
  var fenced = text.match(/^(`{3,})[^\n]*\n([\s\S]*?)\n\1\s*$/)
  return fenced ? fenced[2] : text
}

function previewOf(text, max) {
  var s = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim()
  var n = typeof max === "number" && max > 0 ? Math.floor(max) : 80
  if (s.length <= n) return s
  return s.substring(0, n - 1) + "…"
}

function relativeTime(thenMs, nowMs) {
  var then = Number(thenMs)
  var now = Number(nowMs)
  if (!isFinite(then) || !isFinite(now) || then <= 0) return ""
  var secs = Math.round((now - then) / 1000)
  if (secs < 0) secs = 0
  if (secs < 60) return "just now"
  var mins = Math.floor(secs / 60)
  if (mins < 60) return mins + "m ago"
  var hours = Math.floor(mins / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(months / 12) + "y ago"
}

// ---------------------------------------------------------------- search ----

function makeHit(path, lineNumber, text, folder) {
  var page = pageNameFromFile(basename(path))
  var n = parseInt(lineNumber, 10)
  var raw = String(text === undefined || text === null ? "" : text).replace(/\s+$/, "")
  return {
    path: cleanPath(path),
    page: page,
    line: (isFinite(n) && n > 0) ? n : 1,
    text: raw,
    preview: previewOf(raw, 110),
    folder: String(folder === undefined || folder === null ? "" : folder)
  }
}

// `rg --json` emits one JSON object per line; anything unparseable is skipped
// rather than aborting the whole result set.
function parseRipgrepJson(stdout, folder) {
  var lines = String(stdout === undefined || stdout === null ? "" : stdout).split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line || line.charAt(0) !== "{") continue
    var obj
    try { obj = JSON.parse(line) } catch (e) { continue }
    if (!obj || obj.type !== "match" || !obj.data) continue
    var path = (obj.data.path && obj.data.path.text) ? String(obj.data.path.text) : ""
    var text = (obj.data.lines && obj.data.lines.text) ? String(obj.data.lines.text) : ""
    if (!path) continue
    out.push(makeHit(path, obj.data.line_number, text, folder))
  }
  return out
}

// Fallback for boxes without ripgrep. `grep -rnI` prints path:line:text.
function parseGrepOutput(stdout, folder) {
  var lines = String(stdout === undefined || stdout === null ? "" : stdout).split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(.*?):(\d+):([\s\S]*)$/)
    if (!m) continue
    out.push(makeHit(m[1], m[2], m[3], folder))
  }
  return out
}

function groupHitsByPage(hits) {
  var list = Array.isArray(hits) ? hits : []
  var order = []
  var byPage = {}
  for (var i = 0; i < list.length; i++) {
    var h = list[i]
    if (!h || !h.page) continue
    if (!byPage[h.page]) {
      byPage[h.page] = { page: h.page, path: h.path, hits: [] }
      order.push(h.page)
    }
    byPage[h.page].hits.push(h)
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(byPage[order[j]])
  return out
}

// ------------------------------------------------------- vault discovery ----

// ~/.config/obsidian/obsidian.json is Obsidian's own registry of vaults.
function parseVaults(rawJson) {
  var text = String(rawJson === undefined || rawJson === null ? "" : rawJson).trim()
  if (!text) return []
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return [] }
  if (!isObject(parsed) || !isObject(parsed.vaults)) return []
  var out = []
  for (var key in parsed.vaults) {
    if (!Object.prototype.hasOwnProperty.call(parsed.vaults, key)) continue
    var v = parsed.vaults[key]
    if (!isObject(v) || !v.path) continue
    var path = cleanPath(v.path)
    if (!path) continue
    out.push({ path: path, name: basename(path), ts: Number(v.ts) || 0, open: v.open === true })
  }
  out.sort(function (a, b) { return b.ts - a.ts })
  return out
}

// --------------------------------------------- managed markdown sections ----

// ObsNote owns the text between its markers and nothing else, so a hand-edited
// index page survives every regeneration.
function sectionMarkers(key) {
  var k = String(key === undefined || key === null ? "section" : key).replace(/[^a-z0-9_-]/gi, "")
  return { start: "<!-- obsnote:" + k + ":start -->", end: "<!-- obsnote:" + k + ":end -->" }
}

function replaceMarkedSection(existing, key, body) {
  var text = String(existing === undefined || existing === null ? "" : existing).replace(/\r/g, "")
  var marks = sectionMarkers(key)
  var inner = String(body === undefined || body === null ? "" : body).replace(/\s+$/, "")
  var content = marks.start + "\n" + inner + "\n" + marks.end
  var startIndex = text.indexOf(marks.start)
  var endIndex = text.indexOf(marks.end)
  if (startIndex !== -1 && endIndex !== -1 && endIndex > startIndex) {
    return text.substring(0, startIndex) + content + text.substring(endIndex + marks.end.length)
  }
  var head = text.replace(/\s+$/, "")
  return head ? head + "\n\n" + content + "\n" : content + "\n"
}

function indexSectionBody(cfg) {
  var c = normalizeConfig(cfg)
  var label = basename(c.folder)
  return "## " + label + "\n\n- [[" + folderNoteRelative(c).replace(/\.md$/i, "") + "|" + label
    + "]] — scratchpad captures from the bar"
}

// Accepts either file names ("Inbox.md") or the panel's own page names
// ("Inbox") -- the folder note is written from the live page list, which
// carries no extension, while tests and callers reading a directory carry one.
function pageListForNote(names, cfg) {
  var c = normalizeConfig(cfg)
  var reserved = basename(c.folder).toLowerCase()
  var list = Array.isArray(names) ? names : []
  var seen = {}
  var out = []
  for (var i = 0; i < list.length; i++) {
    var name = sanitizePageName(list[i])
    if (!name) continue
    var key = name.toLowerCase()
    if (key === reserved || seen[key]) continue
    seen[key] = true
    out.push(name)
  }
  out.sort(function (a, b) {
    var x = a.toLowerCase(), y = b.toLowerCase()
    return x < y ? -1 : (x > y ? 1 : 0)
  })
  return out
}

function folderNoteBody(cfg, pageNames) {
  var c = normalizeConfig(cfg)
  var pages = pageListForNote(pageNames, c)
  if (!pages.length) return "_No pages yet. Capture something from the bar._"
  var lines = []
  for (var i = 0; i < pages.length; i++) {
    lines.push("- [[" + c.folder + "/" + pages[i] + "|" + pages[i] + "]]")
  }
  return lines.join("\n")
}

function folderNoteContent(cfg, pageNames, date) {
  var c = normalizeConfig(cfg)
  var label = basename(c.folder)
  var head = "---\ntags:\n  - obsnote\n---\n\n# " + label
    + "\n\nCaptured from the Omarchy bar by ObsNote. Updated " + formatStamp(date) + ".\n"
  return replaceMarkedSection(head, "pages", folderNoteBody(c, pageNames))
}

// Returns null when the line is already there, so callers can skip the write.
function ensureLine(existing, line) {
  var text = String(existing === undefined || existing === null ? "" : existing).replace(/\r/g, "")
  var want = String(line === undefined || line === null ? "" : line).trim()
  if (!want) return null
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === want) return null
  }
  var head = text.replace(/\s+$/, "")
  return head ? head + "\n" + want + "\n" : want + "\n"
}

function gitignoreLine(cfg) {
  var c = normalizeConfig(cfg)
  return c.folder ? "/" + c.folder + "/" : ""
}

function hyprlandBinding() {
  return "bindd = SUPER SHIFT, N, ObsNote quick capture, exec, omarchy-shell obsnote quickCapture"
}

// ----------------------------------------------------------------- store ----

function normalizeStringList(raw, limit) {
  var list = Array.isArray(raw) ? raw : []
  var max = (typeof limit === "number" && limit > 0) ? limit : 20
  var seen = {}
  var out = []
  for (var i = 0; i < list.length && out.length < max; i++) {
    var s = String(list[i] === undefined || list[i] === null ? "" : list[i]).trim()
    if (!s || seen[s]) continue
    seen[s] = true
    out.push(s)
  }
  return out
}

function emptyStore() {
  return {
    version: STORE_VERSION,
    config: normalizeConfig(DEFAULT_CONFIG),
    lastPage: "",
    pinned: [],
    recentQueries: []
  }
}

function normalizeStore(raw) {
  var src = isObject(raw) ? raw : {}
  return {
    version: STORE_VERSION,
    config: normalizeConfig(src.config),
    lastPage: sanitizePageName(str(src.lastPage, "")),
    pinned: normalizeStringList(src.pinned, 20),
    recentQueries: normalizeStringList(src.recentQueries, 10)
  }
}

function parseStore(rawText) {
  var text = String(rawText === undefined || rawText === null ? "" : rawText).trim()
  if (!text) return emptyStore()
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return emptyStore() }
  if (!isObject(parsed)) return emptyStore()
  if (Number(parsed.version) !== STORE_VERSION) return emptyStore()
  return normalizeStore(parsed)
}

function serializeStore(store) {
  return JSON.stringify(normalizeStore(store), null, 2) + "\n"
}

function togglePinned(pinned, page) {
  var name = sanitizePageName(page)
  var list = normalizeStringList(pinned, 20)
  if (!name) return list
  var out = []
  var found = false
  for (var i = 0; i < list.length; i++) {
    if (list[i] === name) { found = true; continue }
    out.push(list[i])
  }
  if (!found) out.unshift(name)
  return normalizeStringList(out, 20)
}

// Pinned pages float to the top of every picker, in pin order.
function orderPages(pages, pinned) {
  var all = Array.isArray(pages) ? pages : []
  var pins = normalizeStringList(pinned, 20)
  var isPinned = {}
  for (var i = 0; i < pins.length; i++) isPinned[pins[i]] = true
  var top = []
  for (var j = 0; j < pins.length; j++) {
    for (var k = 0; k < all.length; k++) {
      if (all[k] === pins[j]) { top.push(all[k]); break }
    }
  }
  var rest = []
  for (var m = 0; m < all.length; m++) {
    if (!isPinned[all[m]]) rest.push(all[m])
  }
  return top.concat(rest)
}

function pushRecentQuery(queries, query) {
  var q = String(query === undefined || query === null ? "" : query).trim()
  if (!q) return normalizeStringList(queries, 10)
  var list = normalizeStringList(queries, 10)
  var out = [q]
  for (var i = 0; i < list.length; i++) {
    if (list[i] !== q) out.push(list[i])
  }
  return normalizeStringList(out, 10)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    STORE_VERSION: STORE_VERSION,
    DEFAULT_CONFIG: DEFAULT_CONFIG,
    FORMATS: FORMATS,
    normalizeConfig: normalizeConfig,
    configIssues: configIssues,
    configReady: configReady,
    cleanPath: cleanPath,
    basename: basename,
    sanitizeFolder: sanitizeFolder,
    sanitizeRelative: sanitizeRelative,
    sanitizeSegment: sanitizeSegment,
    sanitizePageName: sanitizePageName,
    folderPath: folderPath,
    attachmentsPath: attachmentsPath,
    pagePath: pagePath,
    pageRelative: pageRelative,
    indexPath: indexPath,
    folderNoteRelative: folderNoteRelative,
    folderNotePath: folderNotePath,
    pageNameFromFile: pageNameFromFile,
    listablePages: listablePages,
    pageListForNote: pageListForNote,
    obsidianUri: obsidianUri,
    formatStamp: formatStamp,
    formatIso: formatIso,
    attachmentFileName: attachmentFileName,
    isCommandLine: isCommandLine,
    isCodeLike: isCodeLike,
    looksLikeJson: looksLikeJson,
    guessLanguage: guessLanguage,
    suggestFormat: suggestFormat,
    escapeMarkdownLabel: escapeMarkdownLabel,
    prefixLines: prefixLines,
    fenceFor: fenceFor,
    renderBody: renderBody,
    sourceLine: sourceLine,
    renderBlock: renderBlock,
    imageEmbed: imageEmbed,
    newPageHeader: newPageHeader,
    stripFrontMatter: stripFrontMatter,
    parseBlocks: parseBlocks,
    blockCopyText: blockCopyText,
    previewOf: previewOf,
    relativeTime: relativeTime,
    parseRipgrepJson: parseRipgrepJson,
    parseGrepOutput: parseGrepOutput,
    groupHitsByPage: groupHitsByPage,
    parseVaults: parseVaults,
    sectionMarkers: sectionMarkers,
    replaceMarkedSection: replaceMarkedSection,
    indexSectionBody: indexSectionBody,
    folderNoteBody: folderNoteBody,
    folderNoteContent: folderNoteContent,
    ensureLine: ensureLine,
    gitignoreLine: gitignoreLine,
    hyprlandBinding: hyprlandBinding,
    emptyStore: emptyStore,
    normalizeStore: normalizeStore,
    parseStore: parseStore,
    serializeStore: serializeStore,
    togglePinned: togglePinned,
    orderPages: orderPages,
    pushRecentQuery: pushRecentQuery
  }
}
