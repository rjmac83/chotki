import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: glossary
    objectName: "glossary"
    width: parent ? parent.width : 800
    height: parent ? parent.height : 700

    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"
    property string openSlug: ""
    property bool searchLive: false

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }
    function face() { return charter.status === FontLoader.Ready ? charter.name : "serif" }

    readonly property var entry: bridge.glossaryEntry || ({})
    readonly property bool showingEntry: (entry.slug || "").length > 0

    function present(slug) {
        openSlug = slug || ""
        bridge.showGlossary(openSlug, queryField.text || "")
    }

    function openTerm(slug) {
        openSlug = slug || ""
        bridge.showGlossary(openSlug, queryField.text || "")
    }

    Component.onCompleted: {
        present(window.glossaryPending || "")
        searchLive = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // A bare Label keeps width 0, so its MouseArea never contains the click.
        Item {
            objectName: "glossary-back"
            Layout.preferredWidth: backLabel.implicitWidth + 12
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignLeft
            Label {
                id: backLabel
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2190 Back"
                color: glossary.muted
                font.pixelSize: 13
            }
            MouseArea {
                anchors.fill: parent
                onClicked: window.closeGlossary()
            }
        }

        Label {
            objectName: "glossary-note"
            Layout.fillWidth: true
            text: bridge.glossaryNote
            color: glossary.faint
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            bottomPadding: 10
        }

        TextField {
            id: queryField
            objectName: "glossary-search"
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            placeholderText: "Search terms"
            color: glossary.parchment
            placeholderTextColor: glossary.faint
            font.pixelSize: 14
            selectByMouse: true
            background: Rectangle { color: "transparent" }
            onTextChanged: {
                if (!glossary.searchLive) return
                bridge.showGlossary(glossary.openSlug, text)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: glossary.line }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Flickable {
            id: scroller
            objectName: "glossary-scroll"
            anchors.fill: parent
            contentWidth: width
            contentHeight: page.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: true

            Column {
                id: page
                width: scroller.width
                spacing: 0

                Column {
                    width: parent.width
                    visible: glossary.showingEntry
                    spacing: 8
                    topPadding: 16
                    bottomPadding: 24

                    Item {
                        objectName: "glossary-all"
                        width: allLabel.implicitWidth + 12
                        height: 24
                        Label {
                            id: allLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u2190 All terms"
                            color: glossary.muted
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            preventStealing: true
                            onClicked: glossary.openTerm("")
                        }
                    }
                    Row {
                        spacing: 8
                        Label {
                            objectName: "glossary-term"
                            text: glossary.entry.term || ""
                            color: glossary.gold
                            font.family: glossary.face()
                            font.pixelSize: 24
                        }
                        Label {
                            objectName: "glossary-pronunciation"
                            visible: text.length > 0
                            text: glossary.entry.pronunciation || ""
                            color: glossary.faint
                            font.pixelSize: 13
                        }
                    }
                    Label {
                        objectName: "glossary-body"
                        width: parent.width
                        text: glossary.entry.full || ""
                        color: glossary.parchment
                        font.family: glossary.face()
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                        lineHeight: 1.35
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: glossary.line
                        visible: (glossary.entry.related || []).length > 0
                    }
                    Label {
                        visible: (glossary.entry.related || []).length > 0
                        text: "See also"
                        color: glossary.faint
                        font.pixelSize: 12
                    }
                    // Rows are placed by hand. A Column reports the right offsets
                    // and then delivers every click to the last row.
                    Item {
                        id: relatedList
                        width: parent.width
                        visible: (glossary.entry.related || []).length > 0
                        height: visible ? relatedRepeater.count * 26 : 0

                        Repeater {
                            id: relatedRepeater
                            model: glossary.entry.related || []
                            delegate: Item {
                                required property int index
                                required property var modelData
                                objectName: "glossary-related-" + modelData.slug
                                y: index * 26
                                width: relatedList.width
                                height: 26
                                Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.term
                                    color: glossary.gold
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    preventStealing: true
                                    onClicked: glossary.openTerm(modelData.slug)
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: !glossary.showingEntry
                    spacing: 0
                    bottomPadding: 16

                    Repeater {
                        model: bridge.glossaryCategories
                        delegate: Column {
                            required property var modelData
                            width: page.width
                            spacing: 0
                            Label {
                                objectName: "glossary-category"
                                width: parent.width
                                text: modelData.name
                                color: glossary.gold
                                font.pixelSize: 13
                                topPadding: 16
                                bottomPadding: 4
                            }
                            Repeater {
                                model: modelData.terms || []
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width
                                    height: termColumn.implicitHeight + 12
                                    objectName: "glossary-row-" + modelData.slug
                                    Column {
                                        id: termColumn
                                        y: 6
                                        width: parent.width
                                        spacing: 1
                                        Label {
                                            width: parent.width
                                            text: modelData.term
                                            color: glossary.parchment
                                            font.pixelSize: 15
                                        }
                                        Label {
                                            width: parent.width
                                            text: modelData.short
                                            color: glossary.muted
                                            font.pixelSize: 13
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        preventStealing: true
                                        onClicked: glossary.openTerm(modelData.slug)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            EdgeFade {
                y: scroller.contentY
                width: scroller.width
                height: scroller.height
                z: 8
            }
            }
        }
    }
}
