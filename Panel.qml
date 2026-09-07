// Panel.qml -- the popup, and every piece of ObsNote's state. Not declared as
// an entry point: the bar widget loads it with a Loader, eagerly, so quick
// capture and the IPC surface work while the popup has never been opened.
//
// Everything that touches the vault goes through here. The views are dumb:
// they read `panel.*` and call `panel.*()`.
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "tpelicano.obsnote"
  ipcTarget: "obsnote"
  // We declare our own IpcHandler below (the capture surface is the point of
  // the plugin), so disable the inherited one rather than double-registering.
  manageIpc: false

  // Handed over by BarWidget.injectPanel().
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string glyph: "\uF249"

  // ---- state ---------------------------------------------------------------
  // Never mutated in place -- QML cannot see that. Copy, change, reassign.
  property var store: Model.emptyStore()
  readonly property var cfg: root.store.config
  readonly property bool ready: Model.configReady(root.cfg)
  readonly property var issues: Model.configIssues(root.cfg)

  property bool storeLoaded: false
  property string lastWritten: ""

  property string mode: "capture"          // capture | browse | search | setup
  property var pages: []
  readonly property var orderedPages: Model.orderPages(root.pages, root.store.pinned)

  property string clipText: ""
  property bool clipHasImage: false
  property bool clipHasText: false
  property var sourceInfo: ({})

  property string selectedPage: ""
  property string pageText: ""
  readonly property var pageBlocks: Model.parseBlocks(root.pageText)

  property var searchResults: []
  property string searchQuery: ""
  property bool searching: false
  property bool hasRipgrep: false
  property var vaults: []
  property bool vaultIsGit: false

  property bool busy: false
  property string statusText: ""
  property string statusKind: ""           // ok | error | ""
  property bool fieldFocused: false
  property bool popupOpen: false

  readonly property string folderPath: Model.folderPath(root.cfg)
  readonly property string pageCountLabel: root.pages.length === 1 ? "1 page" : (root.pages.length + " pages")

  // ---- helpers -------------------------------------------------------------

  function q(value) { return Util.shellQuote(value) }

  function say(text, kind) {
    root.statusText = String(text || "")
    root.statusKind = String(kind || "")
    statusTimer.restart()
  }

  function notify(headline, description) {
    if (!root.cfg.notify) return
    Util.execArgv(["omarchy-notification-send", "--app-name", "ObsNote",
                   "-g", root.glyph, String(headline), String(description || "")])
  }

  function copyToClipboard(text) {
    var value = String(text === undefined || text === null ? "" : text)
    if (!value) { root.say("Nothing to copy", "error"); return }
    Quickshell.execDetached(["bash", "-c", "printf '%s' " + root.q(value) + " | wl-copy"])
    root.say("Copied " + value.length + " chars", "ok")
  }

  function openInObsidian(page) {
    var relative = page ? Model.pageRelative(root.cfg, page) : Model.folderNoteRelative(root.cfg)
    var uri = Model.obsidianUri(root.cfg.vaultName, relative)
    if (!uri) { root.say("No vault configured", "error"); return }
    Util.execArgv(["xdg-open", uri])
  }

  function openFolderInObsidian() { root.openInObsidian("") }

  function setMode(next) {
    root.mode = String(next)
    if (root.mode === "capture") root.probeContext()
    if (root.mode === "browse" && !root.selectedPage) root.selectPage(root.cfg.defaultPage)
  }

  // ---- persisted state -----------------------------------------------------

  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/obsnote"
  readonly property string storePath: stateDir + "/state.json"

  function applyStore(text) {
    var parsed = Model.parseStore(text)
    root.store = parsed
    root.storeLoaded = true
    if (!root.selectedPage) root.selectedPage = parsed.lastPage || parsed.config.defaultPage
  }

  function mutateStore(patch) {
    var next = {}
    for (var k in root.store) next[k] = root.store[k]
    for (var p in patch) next[p] = patch[p]
    root.store = Model.normalizeStore(next)
    saveDebounce.restart()
  }

  function setConfig(key, value) {
    var nextConfig = {}
    for (var k in root.cfg) nextConfig[k] = root.cfg[k]
    nextConfig[key] = value
    if (key === "vaultPath") nextConfig.vaultName = Model.basename(value)
    root.mutateStore({ config: Model.normalizeConfig(nextConfig) })
  }

  function flushStore() {
    if (!root.storeLoaded) return
    var payload = Model.serializeStore(root.store)
    if (payload === root.lastWritten) return
    root.lastWritten = payload
    storeFile.setText(payload)
  }

  Process { id: ensureDir; command: ["mkdir", "-p", root.stateDir]; onExited: storeFile.reload() }
  Timer { id: saveDebounce; interval: 300; onTriggered: root.flushStore() }
  Timer { id: statusTimer; interval: 5000; onTriggered: { root.statusText = ""; root.statusKind = "" } }

  Component.onCompleted: {
    ensureDir.running = true
    ripgrepProbe.running = true
    vaultRegistry.reload()
  }

  FileView {
    id: storeFile
    path: root.storePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: storeFile.reload()
    // Our own write echoing back would stomp whatever was typed since.
    onLoaded: {
      var incoming = storeFile.text()
      if (incoming === root.lastWritten) return
      root.applyStore(incoming)
    }
    // Required, not defensive: the file does not exist on a first run and
    // would otherwise never be created.
    onLoadFailed: {
      if (root.storeLoaded) return
      root.applyStore("")
      root.flushStore()
    }
  }

  // ---- vault discovery -----------------------------------------------------

  // Obsidian's own registry, so the setup view can offer real vaults instead of
  // asking the user to type a path.
  FileView {
    id: vaultRegistry
    path: Quickshell.env("HOME") + "/.config/obsidian/obsidian.json"
    watchChanges: false
    printErrors: false
    onLoaded: root.vaults = Model.parseVaults(vaultRegistry.text())
    onLoadFailed: root.vaults = []
  }

  Process {
    id: gitProbe
    command: ["test", "-d", root.cfg.vaultPath + "/.git"]
    onExited: function (code) { root.vaultIsGit = code === 0 }
  }

  onCfgChanged: if (root.cfg.vaultPath) gitProbe.running = true

  // ---- page listing --------------------------------------------------------

  function rebuildPages() {
    var names = []
    for (var i = 0; i < folderModel.count; i++) {
      names.push(String(folderModel.get(i, "fileName")))
    }
    root.pages = Model.listablePages(names, root.cfg)
  }

  function reloadPages() {
    // Re-pointing the model is the only way to force a rescan of a folder that
    // did not exist when the model was first given the URL.
    var url = folderModel.folder
    folderModel.folder = ""
    folderModel.folder = url
  }

  FolderListModel {
    id: folderModel
    folder: root.folderPath ? Util.fileUrl(root.folderPath) : ""
    nameFilters: ["*.md"]
    showDirs: false
    showFiles: true
    showHidden: false
    sortField: FolderListModel.Name
    onCountChanged: root.rebuildPages()
    onFolderChanged: root.rebuildPages()
  }

  // ---- clipboard + source context -----------------------------------------

  function probeContext() {
    clipTypes.running = true
    sourceProbe.running = true
  }

  Process {
    id: clipTypes
    command: ["wl-paste", "--list-types"]
    stdout: StdioCollector { id: clipTypesOut; waitForEnd: true }
    onExited: function (code) {
      var types = code === 0 ? String(clipTypesOut.text || "") : ""
      root.clipHasImage = /image\/(png|jpeg|webp|bmp)/i.test(types)
      root.clipHasText = /text\//i.test(types)
      if (!root.captureChain) {
        if (root.clipHasText) clipTextProc.running = true
        else root.clipText = ""
        return
      }
      // Tail of the capture chain: the source and the clipboard's real types
      // are both known now, so the right branch can be picked once.
      root.captureChain = false
      if (root.clipHasText) freshClip.running = true
      else if (root.clipHasImage) root.captureClipboardImage(root.pendingCapturePage)
      else root.say("Clipboard is empty", "error")
    }
  }

  Process {
    id: clipTextProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector { id: clipTextOut; waitForEnd: true }
    onExited: function (code) {
      root.clipText = code === 0 ? String(clipTextOut.text || "") : ""
    }
  }

  // The window that was focused when the bar was clicked -- a layer-shell popup
  // is not a toplevel, so hyprctl still reports the user's real window.
  Process {
    id: sourceProbe
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector { id: sourceOut; waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) { root.sourceInfo = ({}); return }
      var parsed = null
      try { parsed = JSON.parse(String(sourceOut.text || "")) } catch (e) { parsed = null }
      if (!parsed || typeof parsed !== "object") { root.sourceInfo = ({}); return }
      root.sourceInfo = {
        app: String(parsed.initialClass || parsed.class || ""),
        title: String(parsed.title || "")
      }
    }
    // Probing is async, so a capture that fired the probe has to wait for it
    // or the first capture of a session lands with no source stamped.
    onRunningChanged: if (!running && root.captureChain) clipTypes.running = true
  }

  Timer {
    id: clipPoll
    interval: 1500
    repeat: true
    running: root.opened && root.mode === "capture"
    onTriggered: clipTypes.running = true
  }

  // ---- capture -------------------------------------------------------------

  property var appendQueue: []
  property var appendJob: null
  property string appendPayload: ""

  // The append is a real `>>`: read-modify-write would lose whatever Obsidian
  // wrote to the same page in between, and the payload rides in on stdin so a
  // megabyte of clipboard never has to survive shell quoting.
  function appendToPage(page, payload, label) {
    var name = Model.sanitizePageName(page) || root.cfg.defaultPage
    if (!root.ready) { root.setMode("setup"); root.say("Finish setup first", "error"); return }
    if (!payload) { root.say("Nothing to capture", "error"); return }
    var queue = root.appendQueue.slice()
    queue.push({ page: name, payload: String(payload), label: String(label || "Captured") })
    root.appendQueue = queue
    root.pumpAppend()
  }

  function pumpAppend() {
    if (root.appendJob || root.appendQueue.length === 0) return
    var queue = root.appendQueue.slice()
    var job = queue.shift()
    root.appendQueue = queue
    root.appendJob = job
    root.busy = true

    var file = Model.pagePath(root.cfg, job.page)
    var header = Model.newPageHeader(job.page, new Date())
    var script = "set -e\n"
      + "dir=" + root.q(root.folderPath) + "\n"
      + "file=" + root.q(file) + "\n"
      + "mkdir -p -- \"$dir\"\n"
      + "if [ ! -s \"$file\" ]; then printf '%s' " + root.q(header) + " > \"$file\"; fi\n"
      + "cat >> \"$file\"\n"
    root.appendPayload = job.payload
    appendProc.command = ["bash", "-c", script]
    appendProc.stdinEnabled = true
    appendProc.running = true
  }

  Process {
    id: appendProc
    onStarted: {
      appendProc.write(root.appendPayload)
      appendProc.stdinEnabled = false
    }
    onExited: function (code) {
      var job = root.appendJob
      root.appendJob = null
      root.busy = root.appendQueue.length > 0
      if (!job) return
      if (code === 0) {
        root.mutateStore({ lastPage: job.page })
        root.say(job.label + " → " + job.page, "ok")
        root.notify("Captured to " + job.page, Model.previewOf(job.payload, 90))
        // FolderListModel watches the folder itself; a rescan is only needed
        // when the capture is what created the folder in the first place.
        if (root.pages.length === 0) root.reloadPages()
        if (root.selectedPage === job.page) pageFile.reload()
      } else {
        root.say("Could not write to " + job.page, "error")
        root.notify("ObsNote capture failed", "Could not write to " + job.page)
      }
      Qt.callLater(root.pumpAppend)
    }
  }

  // The one place a capture is composed. Everything else -- the panel button,
  // the right-click, the hotkey, IPC -- funnels through it.
  function captureText(text, page, format, label) {
    var body = String(text === undefined || text === null ? "" : text)
    if (!body.trim()) { root.say("Clipboard is empty", "error"); return }
    var chosen = format ? String(format) : Model.suggestFormat(body, root.cfg)
    var block = Model.renderBlock({
      config: root.cfg,
      text: body,
      format: chosen,
      date: new Date(),
      source: root.sourceInfo
    })
    root.appendToPage(page, block, label || "Captured")
  }

  // Always re-read the clipboard and the focused window rather than trusting
  // the poll: the user may have copied something a hundred milliseconds ago,
  // and the panel does not poll at all while it is closed.
  function captureClipboard(page, format) {
    if (!root.ready) { root.setMode("setup"); root.say("Finish setup first", "error"); return }
    root.pendingCapturePage = Model.sanitizePageName(page) || root.cfg.defaultPage
    root.pendingCaptureFormat = format ? String(format) : ""
    root.captureChain = true
    sourceProbe.running = true
  }

  property string pendingCapturePage: ""
  property string pendingCaptureFormat: ""
  property bool captureChain: false

  Process {
    id: freshClip
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector { id: freshClipOut; waitForEnd: true }
    onExited: function (code) {
      var text = code === 0 ? String(freshClipOut.text || "") : ""
      root.clipText = text
      if (!text.trim()) {
        if (root.clipHasImage) { root.captureClipboardImage(root.pendingCapturePage); return }
        root.say("Clipboard is empty", "error")
        return
      }
      root.captureText(text, root.pendingCapturePage, root.pendingCaptureFormat, "Captured")
    }
  }

  function quickCapture() { root.captureClipboard(root.cfg.defaultPage, "") }

  // ---- images --------------------------------------------------------------

  property string pendingImagePage: ""
  property string pendingImageName: ""

  function captureClipboardImage(page) {
    if (!root.ready) { root.setMode("setup"); root.say("Finish setup first", "error"); return }
    root.pendingImagePage = Model.sanitizePageName(page) || root.cfg.defaultPage
    root.pendingImageName = Model.attachmentFileName(new Date(), "png")
    // Stamp the window that was focused before the grab, not after it.
    sourceProbe.running = true
    var dir = Model.attachmentsPath(root.cfg)
    var file = dir + "/" + root.pendingImageName
    root.busy = true
    imageProc.command = ["bash", "-c",
      "set -e\nmkdir -p -- " + root.q(dir) + "\nwl-paste --type image/png > " + root.q(file)
      + "\ntest -s " + root.q(file)]
    imageProc.running = true
  }

  // grim needs the screen to itself, so the panel gets out of the way first and
  // slurp's own overlay takes over.
  function clipRegion() {
    if (!root.ready) { root.setMode("setup"); root.say("Finish setup first", "error"); return }
    root.pendingImagePage = root.selectedPage || root.cfg.defaultPage
    root.pendingImageName = Model.attachmentFileName(new Date(), "png")
    // Stamp the window that was focused before the grab, not after it.
    sourceProbe.running = true
    var dir = Model.attachmentsPath(root.cfg)
    var file = dir + "/" + root.pendingImageName
    root.close()
    root.busy = true
    imageProc.command = ["bash", "-c",
      "set -e\nmkdir -p -- " + root.q(dir)
      + "\ngeom=$(slurp -d) || exit 1\ngrim -g \"$geom\" " + root.q(file)
      + "\ntest -s " + root.q(file)]
    imageProc.running = true
  }

  Process {
    id: imageProc
    onExited: function (code) {
      root.busy = false
      if (code !== 0) { root.say("No image captured", "error"); return }
      var block = Model.renderBlock({
        config: root.cfg,
        body: Model.imageEmbed(root.cfg, root.pendingImageName, ""),
        date: new Date(),
        source: root.sourceInfo
      })
      root.appendToPage(root.pendingImagePage, block, "Image")
    }
  }

  // ---- browse --------------------------------------------------------------

  function selectPage(page) {
    root.selectedPage = Model.sanitizePageName(page)
    root.pageText = ""
  }

  FileView {
    id: pageFile
    path: root.selectedPage ? Model.pagePath(root.cfg, root.selectedPage) : ""
    watchChanges: true
    printErrors: false
    onFileChanged: pageFile.reload()
    onLoaded: root.pageText = pageFile.text()
    onLoadFailed: root.pageText = ""
  }

  function togglePin(page) {
    root.mutateStore({ pinned: Model.togglePinned(root.store.pinned, page) })
  }

  // ---- search --------------------------------------------------------------

  Process {
    id: ripgrepProbe
    command: ["bash", "-c", "command -v rg >/dev/null 2>&1"]
    onExited: function (code) { root.hasRipgrep = code === 0 }
  }

  property string pendingQuery: ""

  function runSearch(query) {
    var q = String(query === undefined || query === null ? "" : query).trim()
    root.searchQuery = q
    if (!q || !root.folderPath) { root.searchResults = []; root.searching = false; return }
    if (searchProc.running) { root.pendingQuery = q; return }
    root.searching = true
    searchProc.command = root.hasRipgrep
      ? ["rg", "--json", "--smart-case", "--max-columns", "400", "-e", q, "--", root.folderPath]
      : ["grep", "-rnI", "--include=*.md", "-e", q, "--", root.folderPath]
    searchProc.running = true
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: function (code) {
      var text = String(searchOut.text || "")
      root.searchResults = root.hasRipgrep
        ? Model.parseRipgrepJson(text, root.folderPath)
        : Model.parseGrepOutput(text, root.folderPath)
      root.searching = false
      if (root.searchQuery) root.mutateStore({ recentQueries: Model.pushRecentQuery(root.store.recentQueries, root.searchQuery) })
      if (root.pendingQuery) {
        var next = root.pendingQuery
        root.pendingQuery = ""
        Qt.callLater(function () { root.runSearch(next) })
      }
    }
  }

  // ---- vault housekeeping --------------------------------------------------

  TextFileEditor {
    id: editor
    onFinished: function (tag, changed, error) {
      if (error) { root.say(error, "error"); return }
      if (tag === "index") root.say(changed ? "Linked from index page" : "Index page already links here", "ok")
      else if (tag === "gitignore") root.say(changed ? "Added to .gitignore" : "Already in .gitignore", "ok")
    }
  }

  // The folder note is ObsNote's own page, but a user may add prose above the
  // marker; only the marked list is regenerated.
  // FolderListModel repopulates asynchronously, so the folder note has to be
  // written when the page list has actually changed -- writing it straight
  // after an append captured an empty list and published "No pages yet".
  Timer { id: folderNoteDebounce; interval: 600; onTriggered: root.syncFolderNote() }
  onPagesChanged: if (root.ready) folderNoteDebounce.restart()

  function linkIndexIfConfigured() {
    if (root.cfg.indexPage) root.linkFromIndex()
  }

  function syncFolderNote() {
    var path = Model.folderNotePath(root.cfg)
    if (!path) return
    var cfg = root.cfg
    var names = root.pages
    editor.run(path, function (existing) {
      var base = (existing && existing.trim()) ? existing : Model.folderNoteContent(cfg, names, new Date())
      return Model.replaceMarkedSection(base, "pages", Model.folderNoteBody(cfg, names))
    }, "foldernote")
  }

  function linkFromIndex() {
    var path = Model.indexPath(root.cfg)
    if (!path) { root.say("Set an index page first", "error"); return }
    var cfg = root.cfg
    editor.run(path, function (existing) {
      return Model.replaceMarkedSection(existing, "index", Model.indexSectionBody(cfg))
    }, "index")
  }

  function addToGitignore() {
    if (!root.cfg.vaultPath) { root.say("No vault selected", "error"); return }
    var line = Model.gitignoreLine(root.cfg)
    editor.run(root.cfg.vaultPath + "/.gitignore", function (existing) {
      return Model.ensureLine(existing, line)
    }, "gitignore")
  }

  // An empty page is a legitimate thing to want: it is the category you are
  // about to paste into. `>` would truncate an existing page, so refuse when
  // the file is already there rather than racing the user's own notes.
  function createPage(name) {
    var page = Model.sanitizePageName(name)
    if (!page) { root.say("Give the page a name", "error"); return }
    if (!root.ready) { root.setMode("setup"); root.say("Finish setup first", "error"); return }
    var file = Model.pagePath(root.cfg, page)
    var header = Model.newPageHeader(page, new Date())
    root.pendingNewPage = page
    createPageProc.command = ["bash", "-c",
      "set -e\nmkdir -p -- " + root.q(root.folderPath)
      + "\nfile=" + root.q(file)
      + "\nif [ -e \"$file\" ]; then exit 3; fi\nprintf '%s' " + root.q(header) + " > \"$file\""]
    createPageProc.running = true
  }

  property string pendingNewPage: ""

  Process {
    id: createPageProc
    onExited: function (code) {
      var page = root.pendingNewPage
      if (code === 3) { root.say(page + " already exists", "error"); root.selectPage(page); return }
      if (code !== 0) { root.say("Could not create " + page, "error"); return }
      root.say("Created " + page, "ok")
      root.selectPage(page)
      root.mutateStore({ lastPage: page })
      if (root.pages.length === 0) root.reloadPages()
    }
  }

  function createFolder() {
    if (!root.cfg.vaultPath) { root.say("No vault selected", "error"); return }
    createProc.command = ["mkdir", "-p", "--", Model.folderPath(root.cfg), Model.attachmentsPath(root.cfg)]
    createProc.running = true
  }

  Process {
    id: createProc
    onExited: function (code) {
      if (code !== 0) { root.say("Could not create the folder", "error"); return }
      root.say("Folder ready", "ok")
      root.reloadPages()
      root.syncFolderNote()
      root.linkIndexIfConfigured()
    }
  }

  function copyHyprBinding() { root.copyToClipboard(Model.hyprlandBinding()) }

  // ---- IPC -----------------------------------------------------------------
  // Also the scripting surface: bin/obsnote is a thin wrapper over these.

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function quickCapture(): void { root.quickCapture() }
    function captureTo(page: string): void { root.captureClipboard(page, "") }
    function note(text: string): void { root.probeContext(); root.captureText(text, root.cfg.defaultPage, "text", "Note") }
    function noteTo(page: string, text: string): void { root.probeContext(); root.captureText(text, page, "text", "Note") }
    function clip(): void { root.clipRegion() }
    function pasteImage(): void { root.captureClipboardImage(root.cfg.defaultPage) }

    function openPage(page: string): void { root.openInObsidian(page) }

    // Open straight onto a tab: `omarchy-shell obsnote view search`.
    function view(name: string): void {
      var wanted = String(name || "").toLowerCase()
      if (["capture", "browse", "search", "setup"].indexOf(wanted) === -1) return
      root.open()
      root.setMode(wanted)
    }

    function linkIndex(): void { root.linkFromIndex() }
    function syncFolder(): void { root.createFolder() }
    function ignoreInGit(): void { root.addToGitignore() }

    function pages(): string { return root.pages.join("\n") }

    // Enough for a shell script to find the vault on disk without guessing.
    function status(): string {
      return JSON.stringify({
        ready: root.ready,
        vaultPath: root.cfg.vaultPath,
        vaultName: root.cfg.vaultName,
        folder: root.cfg.folder,
        folderPath: root.folderPath,
        defaultPage: root.cfg.defaultPage,
        attachments: Model.attachmentsPath(root.cfg),
        pages: root.pages,
        issues: root.issues
      }, null, 2)
    }
  }

  // ---- UI ------------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    onOpenChanged: if (open) root.probeContext()

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.fieldFocused || root.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) {
        if (dy === 0) return
        panelFlick.contentY = Math.max(0, Math.min(
          panelFlick.contentY + dy * Style.space(56),
          Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onTextKey: function (t) {
        if (t === "c") root.setMode("capture")
        else if (t === "b") root.setMode("browse")
        else if (t === "s") root.setMode("search")
        else if (t === "g") root.setMode("setup")
        else if (t === "v") root.captureClipboard(root.selectedPage || root.cfg.defaultPage, "")
        else if (t === "r") root.clipRegion()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "ObsNote"
            meta: root.ready ? (root.cfg.vaultName + " / " + root.cfg.folder) : "Not configured"
            detail: root.ready ? root.pageCountLabel : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.glyph
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "\uF08E"
                tooltipText: "Open the folder in Obsidian"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.ready
                onClicked: root.openFolderInObsidian()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.controlGap

            Button {
              text: "Capture"
              selected: root.mode === "capture"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setMode("capture")
            }
            Button {
              text: "Browse"
              selected: root.mode === "browse"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setMode("browse")
            }
            Button {
              text: "Search"
              selected: root.mode === "search"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setMode("search")
            }
            Button {
              text: "Setup"
              selected: root.mode === "setup"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setMode("setup")
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          CaptureView {
            width: parent.width
            panel: root
            visible: root.mode === "capture"
          }

          BrowseView {
            width: parent.width
            panel: root
            visible: root.mode === "browse"
          }

          SearchView {
            width: parent.width
            panel: root
            visible: root.mode === "search"
          }

          SetupView {
            width: parent.width
            panel: root
            visible: root.mode === "setup"
          }

          Item {
            width: parent.width
            height: statusLabel.implicitHeight
            visible: root.statusText !== ""

            Text {
              id: statusLabel
              width: parent.width
              text: root.statusText
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.statusKind === "error" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
