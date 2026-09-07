// SetupView.qml -- first-run and everything configurable afterwards. The vault,
// the folder, and whether that folder is linked from an index page or hidden
// from git are all the user's calls; ObsNote never makes them silently.
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  required property var panel

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: panel ? panel.urgent : Color.urgent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property var cfg: panel ? panel.cfg : Model.DEFAULT_CONFIG

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- outstanding setup --------------------------------------------------

    Column {
      width: parent.width
      spacing: Style.spacing.xxs
      visible: root.panel && root.panel.issues.length > 0

      Repeater {
        model: root.panel ? root.panel.issues : []

        Text {
          required property var modelData
          width: column.width
          text: "• " + modelData
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // ---- vault --------------------------------------------------------------

    PanelSectionHeader {
      text: "Vault"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      width: parent.width
      visible: root.panel && root.panel.vaults.length === 0
      text: "No vaults found in ~/.config/obsidian/obsidian.json — type a path below."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.panel ? root.panel.vaults : []

        Button {
          required property var modelData
          text: modelData.name
          tooltipText: modelData.path
          selected: root.cfg.vaultPath === modelData.path
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.panel.setConfig("vaultPath", modelData.path)
        }
      }
    }

    TextField {
      id: vaultField
      width: parent.width
      placeholderText: "/absolute/path/to/vault"
      text: root.cfg.vaultPath
      foreground: root.foreground
      font.family: root.fontFamily
      onActiveFocusChanged: root.panel.fieldFocused = activeFocus
      onEditingFinished: if (text !== root.cfg.vaultPath) root.panel.setConfig("vaultPath", text)
    }

    // ---- folder -------------------------------------------------------------

    PanelSectionHeader {
      text: "Capture folder"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      TextField {
        id: folderField
        width: (parent.width - Style.spacing.controlGap) / 2
        placeholderText: "Folder inside the vault"
        text: root.cfg.folder
        foreground: root.foreground
        font.family: root.fontFamily
        onActiveFocusChanged: root.panel.fieldFocused = activeFocus
        onEditingFinished: if (text !== root.cfg.folder) root.panel.setConfig("folder", text)
      }

      TextField {
        id: defaultPageField
        width: (parent.width - Style.spacing.controlGap) / 2
        placeholderText: "Default page"
        text: root.cfg.defaultPage
        foreground: root.foreground
        font.family: root.fontFamily
        onActiveFocusChanged: root.panel.fieldFocused = activeFocus
        onEditingFinished: if (text !== root.cfg.defaultPage) root.panel.setConfig("defaultPage", text)
      }
    }

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      TextField {
        id: attachmentsField
        width: (parent.width - Style.spacing.controlGap) / 2
        placeholderText: "Attachments subfolder"
        text: root.cfg.attachments
        foreground: root.foreground
        font.family: root.fontFamily
        onActiveFocusChanged: root.panel.fieldFocused = activeFocus
        onEditingFinished: if (text !== root.cfg.attachments) root.panel.setConfig("attachments", text)
      }

      TextField {
        id: indexField
        width: (parent.width - Style.spacing.controlGap) / 2
        placeholderText: "Index page, e.g. wiki/index.md"
        text: root.cfg.indexPage
        foreground: root.foreground
        font.family: root.fontFamily
        onActiveFocusChanged: root.panel.fieldFocused = activeFocus
        onEditingFinished: if (text !== root.cfg.indexPage) root.panel.setConfig("indexPage", text)
      }
    }

    Text {
      width: parent.width
      text: root.panel && root.panel.folderPath ? root.panel.folderPath : "No folder resolved yet"
      textFormat: Text.PlainText
      wrapMode: Text.WrapAnywhere
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.xs

      Button {
        text: "Create folder"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.cfg.vaultPath !== ""
        tooltipText: "Make the folder and its attachments subfolder, and write the folder note"
        onClicked: root.panel.createFolder()
      }

      Button {
        text: "Link from index"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.cfg.indexPage !== ""
        tooltipText: "Add a link to the folder note inside an ObsNote-managed section of the index page"
        onClicked: root.panel.linkFromIndex()
      }

      Button {
        text: "Add to .gitignore"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        visible: root.panel && root.panel.vaultIsGit
        tooltipText: "Keep captures out of the vault's git history"
        onClicked: root.panel.addToGitignore()
      }

      Button {
        text: "Copy hotkey binding"
        foreground: root.foreground
        fontFamily: root.fontFamily
        tooltipText: "Copy a Hyprland bind line for quick capture, to paste into your own config"
        onClicked: root.panel.copyHyprBinding()
      }
    }

    // ---- behaviour ----------------------------------------------------------

    PanelSectionHeader {
      text: "Capture behaviour"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "Stamp the source"
      description: "Record the app and window title the capture came from"
      checked: root.cfg.includeSource
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.panel.setConfig("includeSource", !root.cfg.includeSource)
    }

    Toggle {
      width: parent.width
      label: "Fence code automatically"
      description: "Wrap commands and code-looking text in a fenced block"
      checked: root.cfg.autoFence
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.panel.setConfig("autoFence", !root.cfg.autoFence)
    }

    Toggle {
      width: parent.width
      label: "Heading per capture"
      description: "Each capture gets its own timestamped heading"
      checked: root.cfg.timestampHeadings
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.panel.setConfig("timestampHeadings", !root.cfg.timestampHeadings)
    }

    Toggle {
      width: parent.width
      label: "Notify on capture"
      description: "Send a desktop notification after each capture"
      checked: root.cfg.notify
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.panel.setConfig("notify", !root.cfg.notify)
    }

    PanelSeparator { width: parent.width; foreground: root.foreground }

    Text {
      width: parent.width
      text: "Search backend: " + (root.panel && root.panel.hasRipgrep ? "ripgrep" : "grep")
        + "\nSettings file: " + (root.panel ? root.panel.storePath : "")
      textFormat: Text.PlainText
      wrapMode: Text.WrapAnywhere
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
