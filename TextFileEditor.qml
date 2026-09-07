// TextFileEditor.qml -- serialized read-modify-write for the handful of vault
// files ObsNote maintains but does not own outright: the vault index page, the
// folder note, the repo .gitignore. Every one of them is edited in place
// through a marker section, so the read half is mandatory and a blind write
// would destroy user text.
//
// Jobs queue: FileView carries one path at a time and its load/save signals
// are async, so overlapping calls would interleave and write the wrong body to
// the wrong file.
import QtQuick
import Quickshell.Io

Item {
  id: root

  // finished(tag, changed, error) -- `changed` is false both when the
  // transform declined the edit (returned null) and when it failed; `error`
  // distinguishes them.
  signal finished(string tag, bool changed, string error)

  property var _queue: []
  property var _job: null
  property string _phase: "idle"

  // transform(existingText) -> new text, or null to leave the file alone.
  // A file that does not exist yet is handed "" rather than failing.
  function run(path, transform, tag) {
    if (!path || typeof transform !== "function") {
      root.finished(String(tag || ""), false, "no path")
      return
    }
    var queue = root._queue.slice()
    queue.push({ path: String(path), transform: transform, tag: String(tag || "") })
    root._queue = queue
    root._pump()
  }

  function _pump() {
    if (root._job || root._queue.length === 0) return
    var queue = root._queue.slice()
    root._job = queue.shift()
    root._queue = queue
    root._phase = "loading"
    if (file.path === root._job.path) file.reload()
    else file.path = root._job.path
  }

  function _apply(existing) {
    if (!root._job) return
    var next = null
    try {
      next = root._job.transform(existing)
    } catch (e) {
      root._finish(false, String(e))
      return
    }
    if (next === null || next === undefined || String(next) === String(existing)) {
      root._finish(false, "")
      return
    }
    root._phase = "writing"
    file.setText(String(next))
  }

  function _finish(changed, error) {
    var job = root._job
    root._job = null
    root._phase = "idle"
    if (job) root.finished(job.tag, changed === true, String(error || ""))
    Qt.callLater(root._pump)
  }

  FileView {
    id: file
    printErrors: false
    atomicWrites: true
    watchChanges: false

    onLoaded: if (root._phase === "loading") root._apply(file.text())
    onLoadFailed: if (root._phase === "loading") root._apply("")
    onSaved: if (root._phase === "writing") root._finish(true, "")
    onSaveFailed: if (root._phase === "writing") root._finish(false, "could not write file")
  }
}
