// BlockCard.qml -- one capture, shown the same way whether it came from a page
// or from a search hit: heading, a clamped body, and the two actions that make
// the panel useful without Obsidian -- copy it out, or open it in Obsidian.
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string heading: ""
  property string bodyText: ""
  property string trailingNote: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool openEnabled: true
  property int bodyLines: 4

  signal copyRequested()
  signal openRequested()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property bool hot: hover.hovered

  implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX
  radius: Style.cornerRadius
  color: Style.controlFill(false, hot, root.foreground, Color.accent)
  borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", root.foreground, Color.accent)

  HoverHandler { id: hover }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: actions.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.md
    spacing: Style.spacing.xxs

    Text {
      width: parent.width
      visible: root.heading !== ""
      text: root.heading
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      width: parent.width
      visible: root.bodyText !== ""
      text: root.bodyText
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: root.bodyLines
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      width: parent.width
      visible: root.trailingNote !== ""
      text: root.trailingNote
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: Style.spacing.md
    spacing: Style.spacing.xs

    PanelActionButton {
      iconText: "\uF0C5"
      tooltipText: "Copy to clipboard"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.copyRequested()
    }

    PanelActionButton {
      iconText: "\uF08E"
      tooltipText: "Open in Obsidian"
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: root.openEnabled
      onClicked: root.openRequested()
    }
  }
}
