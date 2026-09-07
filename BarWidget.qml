// BarWidget.qml -- bar entry point. Owns the button only; Panel.qml loads
// eagerly through a Loader and owns all state, so captures still work while
// the popup is closed (right-click quick capture, IPC, the global hotkey).
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tpelicano.obsnote"

  // U+F249 nf-fa-sticky_note. Verified by rendering at 14/16/20/24px against
  // JetBrainsMono Nerd Font -- it stays legible where the clipboard glyphs
  // (U+F0EA) turn to mush at bar sizes. `barLabel: "text"` is the fallback
  // for a font subset without it.
  readonly property string glyph: "\uF249"

  readonly property string barLabel: String(root.setting("barLabel", "icon"))
  readonly property string labelText: String(root.setting("labelText", "Notes"))
  readonly property string rightClickAction: String(root.setting("rightClickAction", "quickCapture"))
  readonly property bool showIcon: barLabel !== "text"
  readonly property bool showText: barLabel !== "icon" && labelText !== ""

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property bool busy: panelLoader.item ? panelLoader.item.busy === true : false

  // Panel.qml is loaded standalone, so it needs everything handed to it.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // The bar host mounts one widget per monitor, but only one of them owns the
  // IPC target. `refresh` is the screen-local half of an action that ran once.
  function refresh() { if (panelLoader.item) panelLoader.item.reloadPages() }

  function secondaryAction() {
    var target = panelLoader.item
    if (!target) return
    if (root.rightClickAction === "quickCapture") target.quickCapture()
    else if (root.rightClickAction === "clipRegion") target.clipRegion()
    else if (root.rightClickAction === "openVault") target.openFolderInObsidian()
  }

  // BarIconButton pins itself to `slotSize`, so a text label has to be
  // measured rather than laid out -- TextMetrics does it without a live item.
  TextMetrics {
    id: labelMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    text: root.labelText
  }

  readonly property real contentWidth: {
    var w = 0
    if (root.showIcon) w += Style.bar.iconCanvas
    if (root.showText) w += Math.ceil(labelMetrics.width) + (root.showIcon ? Style.spacing.controlGap : 0)
    return Math.max(Style.bar.statusSlot, w + Style.space(10))
  }

  implicitWidth: vertical ? barSize : contentWidth
  implicitHeight: vertical ? Style.bar.statusSlot : barSize

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.vertical ? Style.bar.statusSlot : root.contentWidth
    active: root.opened
    tooltipText: root.busy ? "ObsNote — working…" : "ObsNote — capture to Obsidian"
    onPressed: function (b) {
      if (b === Qt.RightButton) root.secondaryAction()
      else root.toggle()
    }

    iconComponent: Component {
      Item {
        anchors.centerIn: parent
        width: iconRow.implicitWidth
        height: Style.bar.iconCanvas

        Row {
          id: iconRow
          anchors.centerIn: parent
          spacing: root.showIcon && root.showText ? Style.spacing.controlGap : 0

          Text {
            visible: root.showIcon
            text: root.glyph
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            color: button.active && button.useActiveColor ? button.activeColor : button.foreground
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            opacity: root.busy ? 0.45 : 1.0
            Behavior on opacity { NumberAnimation { duration: 140 } }
          }

          Text {
            visible: root.showText
            text: root.labelText
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            color: button.active && button.useActiveColor ? button.activeColor : button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
