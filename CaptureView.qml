// CaptureView.qml -- what is on the clipboard, where it is going, and how it
// will be formatted. Owns no state of its own beyond the composer draft; the
// panel owns everything that outlives the popup.
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  required property var panel

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  property bool newPageMode: false
  property string chosenFormat: ""
  property string draft: ""

  readonly property string targetPage: panel ? (panel.selectedPage || panel.cfg.defaultPage) : ""
  readonly property string suggestedFormat: panel ? Model.suggestFormat(panel.clipText, panel.cfg) : "text"
  readonly property string effectiveFormat: chosenFormat || suggestedFormat

  readonly property var pageOptions: {
    var out = []
    var list = panel ? panel.orderedPages : []
    var pinned = panel ? panel.store.pinned : []
    for (var i = 0; i < list.length; i++) {
      var isPinned = pinned.indexOf(list[i]) !== -1
      out.push({ value: list[i], label: (isPinned ? "\uF08D  " : "") + list[i] })
    }
    return out
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- clipboard preview --------------------------------------------------

    PanelSectionHeader {
      text: "Clipboard"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    BorderSurface {
      width: parent.width
      implicitHeight: Math.max(Style.space(58), previewColumn.implicitHeight + Style.spacing.rowPaddingX)
      color: Style.controlFill(false, false, root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      Column {
        id: previewColumn
        anchors.left: parent.left
        anchors.right: refreshButton.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.md
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          text: {
            if (!root.panel) return ""
            if (root.panel.clipText.trim()) return Model.previewOf(root.panel.clipText, 220)
            if (root.panel.clipHasImage) return "An image is on the clipboard."
            return "Clipboard is empty."
          }
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
          color: root.panel && (root.panel.clipText.trim() || root.panel.clipHasImage) ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: {
            if (!root.panel) return ""
            var bits = []
            if (root.panel.clipText.trim()) bits.push(root.panel.clipText.length + " chars")
            if (root.panel.clipHasImage) bits.push("image/png")
            var src = root.panel.sourceInfo
            if (src && src.app) bits.push(src.app)
            return bits.join(" · ")
          }
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelActionButton {
        id: refreshButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.spacing.md
        iconText: "\uF021"
        tooltipText: "Re-read the clipboard"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.panel.probeContext()
      }
    }

    // ---- target -------------------------------------------------------------

    PanelSectionHeader {
      text: "Page"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap
      visible: !root.newPageMode

      SearchableDropdown {
        id: pagePicker
        width: parent.width - newPageButton.width - pinButton.width - Style.spacing.controlGap * 2
        showLabel: false
        options: root.pageOptions
        value: root.targetPage
        placeholderText: "Pick a page…"
        emptyText: "No pages yet"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function (v) { root.panel.selectPage(v) }
        onPopupOpenChanged: root.panel.popupOpen = popupOpen
      }

      PanelActionButton {
        id: pinButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uF08D"
        tooltipText: root.panel && root.panel.store.pinned.indexOf(root.targetPage) !== -1
          ? "Unpin this page" : "Pin this page to the top of the list"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.targetPage !== ""
        onClicked: root.panel.togglePin(root.targetPage)
      }

      PanelActionButton {
        id: newPageButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uF067"
        tooltipText: "New page"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: { root.newPageMode = true; Qt.callLater(function () { newPageField.forceActiveFocus() }) }
      }
    }

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap
      visible: root.newPageMode

      TextField {
        id: newPageField
        width: parent.width - createButton.width - cancelButton.width - Style.spacing.controlGap * 2
        placeholderText: "New page name…"
        foreground: root.foreground
        font.family: root.fontFamily
        onActiveFocusChanged: root.panel.fieldFocused = activeFocus
        onAccepted: createButton.clicked()
      }

      Button {
        id: createButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Create"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          var name = Model.sanitizePageName(newPageField.text)
          if (!name) { root.panel.say("Give the page a name", "error"); return }
          root.panel.createPage(name)
          newPageField.text = ""
          root.newPageMode = false
        }
      }

      Button {
        id: cancelButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Cancel"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: { newPageField.text = ""; root.newPageMode = false }
      }
    }

    // ---- format -------------------------------------------------------------

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      Repeater {
        model: Model.FORMATS

        Button {
          required property var modelData
          text: modelData
          selected: root.effectiveFormat === modelData
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          tooltipText: modelData === root.suggestedFormat ? "Detected from the clipboard" : ""
          onClicked: root.chosenFormat = (root.chosenFormat === modelData ? "" : modelData)
        }
      }
    }

    // ---- actions ------------------------------------------------------------

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      Button {
        text: "Capture clipboard"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.panel && !root.panel.busy
        onClicked: root.panel.captureClipboard(root.targetPage, root.chosenFormat)
      }

      Button {
        text: "Paste image"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.panel && root.panel.clipHasImage && !root.panel.busy
        tooltipText: "Save the clipboard image into the vault and embed it"
        onClicked: root.panel.captureClipboardImage(root.targetPage)
      }

      Button {
        text: "Clip region"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.panel && !root.panel.busy
        tooltipText: "Drag a screen region; the PNG lands in the vault"
        onClicked: root.panel.clipRegion()
      }
    }

    // ---- composer -----------------------------------------------------------

    PanelSectionHeader {
      text: "Write it instead"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    BorderSurface {
      width: parent.width
      implicitHeight: Style.space(92)
      color: Style.controlFill(noteArea.activeFocus, false, root.foreground, Color.accent)
      borderSpec: Border.controlSpec(noteArea.activeFocus ? "focus" : "normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      QQC.ScrollView {
        anchors.fill: parent
        anchors.margins: Style.spacing.md
        clip: true

        QQC.TextArea {
          id: noteArea
          placeholderText: "Type a note and press Ctrl+Enter…"
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          color: root.foreground
          placeholderTextColor: Qt.darker(root.foreground, 1.6)
          selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
          selectedTextColor: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          background: null
          onTextChanged: root.draft = text
          onActiveFocusChanged: root.panel.fieldFocused = activeFocus
          Keys.onPressed: function (event) {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                && (event.modifiers & Qt.ControlModifier)) {
              appendNoteButton.clicked()
              event.accepted = true
            }
          }
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      Button {
        id: appendNoteButton
        text: "Append note"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.draft.trim() !== "" && root.panel && !root.panel.busy
        onClicked: {
          if (!noteArea.text.trim()) return
          root.panel.captureText(noteArea.text, root.targetPage, root.chosenFormat || "text", "Note")
          noteArea.text = ""
        }
      }

      Button {
        text: "Clear"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.draft !== ""
        onClicked: noteArea.text = ""
      }
    }
  }
}
