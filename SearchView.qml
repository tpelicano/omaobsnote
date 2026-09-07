// SearchView.qml -- full-text across the capture folder, grouped by page, with
// the same copy / open actions as Browse. ripgrep when it is installed, plain
// grep when it is not; the results look identical either way.
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
  readonly property var groups: panel ? Model.groupHitsByPage(panel.searchResults) : []
  readonly property int hitCount: panel ? panel.searchResults.length : 0

  implicitHeight: column.implicitHeight

  // The panel's key catcher takes bare letters as navigation, so arriving on
  // this tab has to hand focus to the query field or typing goes nowhere.
  onVisibleChanged: if (visible) Qt.callLater(function () { queryField.forceActiveFocus() })

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      TextField {
        id: queryField
        width: parent.width - searchButton.width - clearButton.width - Style.spacing.controlGap * 2
        placeholderText: root.panel && root.panel.hasRipgrep ? "Search captures (ripgrep)…" : "Search captures…"
        foreground: root.foreground
        font.family: root.fontFamily
        text: root.panel ? root.panel.searchQuery : ""
        onActiveFocusChanged: root.panel.fieldFocused = activeFocus
        onAccepted: root.panel.runSearch(text)
        onTextChanged: searchDebounce.restart()
      }

      Button {
        id: searchButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Search"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.panel.runSearch(queryField.text)
      }

      Button {
        id: clearButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Clear"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: queryField.text !== ""
        onClicked: { queryField.text = ""; root.panel.runSearch("") }
      }
    }

    // Typing shouldn't spawn a process per keystroke, and a short pause is
    // what "search as you type" actually means at these result sizes.
    Timer {
      id: searchDebounce
      interval: 320
      onTriggered: root.panel.runSearch(queryField.text)
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.xs
      visible: root.panel && root.panel.store.recentQueries.length > 0 && queryField.text === ""

      Repeater {
        model: root.panel ? root.panel.store.recentQueries : []

        Button {
          required property var modelData
          text: modelData
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: { queryField.text = modelData; root.panel.runSearch(modelData) }
        }
      }
    }

    Text {
      width: parent.width
      text: {
        if (!root.panel) return ""
        if (root.panel.searching) return "Searching…"
        if (!root.panel.searchQuery) return "Type to search every capture page."
        if (root.hitCount === 0) return "No matches for “" + root.panel.searchQuery + "”."
        return root.hitCount + (root.hitCount === 1 ? " match in " : " matches in ") + root.groups.length
          + (root.groups.length === 1 ? " page" : " pages")
      }
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.groups

      Column {
        required property var modelData
        width: column.width
        spacing: Style.spacing.xs

        PanelSectionHeader {
          text: modelData.page + " · " + modelData.hits.length
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: modelData.hits

          BlockCard {
            required property var modelData
            width: parent.width
            heading: "line " + modelData.line
            bodyText: modelData.text
            bodyLines: 2
            foreground: root.foreground
            fontFamily: root.fontFamily
            onCopyRequested: root.panel.copyToClipboard(modelData.text)
            onOpenRequested: root.panel.openInObsidian(modelData.page)
          }
        }
      }
    }
  }
}
