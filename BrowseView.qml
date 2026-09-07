// BrowseView.qml -- the pages in the capture folder and, for the selected one,
// its captures newest first. Reading a page here is the point: you copy a
// snippet back out without Obsidian ever starting.
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  required property var panel

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  // Newest capture first -- the file grows downward, the panel reads upward.
  readonly property var blocks: {
    var source = panel ? panel.pageBlocks : []
    var out = []
    for (var i = source.length - 1; i >= 0; i--) out.push(source[i])
    return out
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: "Pages"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      width: parent.width
      visible: root.panel && root.panel.pages.length === 0
      text: root.panel && root.panel.ready
        ? "No pages yet. Capture something and the first page appears here."
        : "Set the vault up first — see the Setup tab."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.panel ? root.panel.orderedPages : []

        Button {
          required property var modelData
          text: (root.panel.store.pinned.indexOf(modelData) !== -1 ? "\uF08D  " : "") + modelData
          selected: root.panel.selectedPage === modelData
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          tooltipText: "Left-click to open · right-click to pin"
          onClicked: root.panel.selectPage(modelData)
          onRightClicked: root.panel.togglePin(modelData)
        }
      }
    }

    PanelSeparator {
      width: parent.width
      visible: root.panel && root.panel.selectedPage !== ""
      foreground: root.foreground
    }

    Item {
      width: parent.width
      height: pageHeaderRow.implicitHeight
      visible: root.panel && root.panel.selectedPage !== ""

      Row {
        id: pageHeaderRow
        width: parent.width
        spacing: Style.spacing.controlGap

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - openPageButton.width - copyPageButton.width - clipHereButton.width - Style.spacing.controlGap * 3
          text: root.panel ? root.panel.selectedPage : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        PanelActionButton {
          id: clipHereButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uF0EA"
          tooltipText: "Capture the clipboard into this page"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: root.panel && !root.panel.busy
          onClicked: root.panel.captureClipboard(root.panel.selectedPage, "")
        }

        PanelActionButton {
          id: copyPageButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uF0C5"
          tooltipText: "Copy the whole page"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: root.panel && root.panel.pageText !== ""
          onClicked: root.panel.copyToClipboard(root.panel.pageText)
        }

        PanelActionButton {
          id: openPageButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uF08E"
          tooltipText: "Open this page in Obsidian"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: root.panel && root.panel.selectedPage !== ""
          onClicked: root.panel.openInObsidian(root.panel.selectedPage)
        }
      }
    }

    Text {
      width: parent.width
      visible: root.panel && root.panel.selectedPage !== "" && root.blocks.length === 0
      text: "This page has no captures yet."
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: root.blocks

      BlockCard {
        required property var modelData
        width: column.width
        heading: modelData.heading
        bodyText: modelData.body
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCopyRequested: root.panel.copyToClipboard(Model.blockCopyText(modelData))
        onOpenRequested: root.panel.openInObsidian(root.panel.selectedPage)
      }
    }
  }
}
