import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: psalter
    objectName: "psalter"
    signal closeRequested()
    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }
    function face() { return charter.status === FontLoader.Ready ? charter.name : "serif" }

    Component.onCompleted: bridge.refreshPsalter()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 16
            Label {
                objectName: "psalter-back"
                text: "Back"
                color: psalter.gold
                font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: psalter.closeRequested()
                }
            }
            Item { Layout.fillWidth: true }
            Label {
                text: "The Psalter"
                color: psalter.parchment
                font.family: psalter.face()
                font.pixelSize: 22
            }
            Item { Layout.fillWidth: true }
            ComboBox {
                objectName: "psalter-browse"
                model: 20
                displayText: "Browse All Kathismata"
                font.pixelSize: 14
                implicitWidth: 210
                onActivated: function(index) { bridge.openKathisma(index + 1, true) }
            }
        }

        Flickable {
            id: reader
            objectName: "psalter-scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            property bool userMoved: false
            property var finishedNumbers: []

            function noteScroll(delta) {
                userMoved = true
                contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + delta))
                Qt.callLater(considerEnds)
            }

            function considerEnds() {
                if (!userMoved) return
                const marks = []
                function walk(item) {
                    if (!item) return
                    const name = item.objectName || ""
                    if (String(name).indexOf("psalter-end-") === 0) marks.push(item)
                    const kids = item.children
                    for (let index = 0; index < kids.length; index++) walk(kids[index])
                }
                walk(column)
                const top = contentY
                const bottom = contentY + height
                for (let index = 0; index < marks.length; index++) {
                    const mark = marks[index]
                    if (!mark.visible) continue
                    const y = mark.mapToItem(column, 0, 0).y
                    if (y < top || y > bottom) continue
                    const number = mark.kathisma
                    if (finishedNumbers.indexOf(number) >= 0) continue
                    finishedNumbers = finishedNumbers.concat([number])
                    bridge.finishPsalter()
                }
            }

            WheelHandler {
                blocking: false
                onWheel: function(event) {
                    if (event.angleDelta.y === 0 && event.pixelDelta.y === 0) return
                    reader.userMoved = true
                    Qt.callLater(reader.considerEnds)
                }
            }

            Column {
                id: column
                width: reader.width
                spacing: 8
                leftPadding: 24
                rightPadding: 24
                topPadding: 12
                bottomPadding: 24

                Label {
                    objectName: "psalter-chosen"
                    width: parent.width - 48
                    visible: bridge.psalterManual >= 1
                    text: "Chosen for Reading"
                    color: psalter.muted
                    font.pixelSize: 13
                }
                Column {
                    width: parent.width - 48
                    spacing: 6
                    visible: bridge.psalterManual >= 1 && bridge.psalterManualKathisma.number !== undefined
                    Label {
                        text: (bridge.psalterManualKathisma.label || "") + "  "
                              + (bridge.psalterManualKathisma.range || "")
                        color: psalter.parchment
                        font.pixelSize: 16
                    }
                    Repeater {
                        model: bridge.psalterManualKathisma.psalms || []
                        delegate: Column {
                            required property var modelData
                            width: column.width - 48
                            spacing: 4
                            Label {
                                text: "Psalm " + modelData.number
                                color: psalter.gold
                                font.pixelSize: 12
                            }
                            Label {
                                width: parent.width
                                visible: modelData.superscription
                                text: modelData.superscription || ""
                                color: psalter.muted
                                font.italic: true
                                font.family: psalter.face()
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: modelData.verses || []
                                delegate: Label {
                                    required property var modelData
                                    width: column.width - 48
                                    text: modelData.number + "  " + modelData.text
                                    color: psalter.parchment
                                    font.family: psalter.face()
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                    Item {
                        objectName: "psalter-end-manual"
                        property int kathisma: bridge.psalterManual
                        width: 1
                        height: 1
                        visible: bridge.psalterManual >= 1
                    }
                }

                Label {
                    objectName: "psalter-empty"
                    width: parent.width - 48
                    visible: bridge.psalterEmpty.length > 0
                    text: bridge.psalterEmpty
                    color: psalter.muted
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                }
                Label {
                    objectName: "psalter-note"
                    width: parent.width - 48
                    visible: bridge.psalterNote.length > 0
                    text: bridge.psalterNote
                    color: psalter.faint
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: bridge.psalterAppointed
                    delegate: Column {
                        id: group
                        required property var modelData
                        required property int index
                        width: column.width - 48
                        spacing: 6
                        Label {
                            text: group.modelData.service
                            color: psalter.gold
                            font.pixelSize: 12
                            topPadding: 4
                        }
                        Repeater {
                            model: group.modelData.kathismata || []
                            delegate: Column {
                                id: row
                                required property var modelData
                                required property int index
                                width: group.width
                                spacing: 6
                                Item {
                                    width: parent.width
                                    height: heading.implicitHeight
                                    Row {
                                        id: heading
                                        width: parent.width
                                        spacing: 8
                                        Label {
                                            text: row.modelData.label + "  " + row.modelData.range
                                            color: psalter.parchment
                                            font.pixelSize: 16
                                        }
                                        Label {
                                            text: row.modelData.open ? "⌃" : "⌄"
                                            color: psalter.gold
                                        }
                                    }
                                    MouseArea {
                                        objectName: group.index === 0 && row.index === 0
                                                    ? "psalter-first" : ("psalter-kathisma-" + row.modelData.number)
                                        anchors.fill: parent
                                        onClicked: bridge.openKathisma(row.modelData.number, false)
                                    }
                                }
                                Column {
                                    width: parent.width
                                    spacing: 4
                                    visible: row.modelData.open
                                    Repeater {
                                        model: row.modelData.psalms || []
                                        delegate: Column {
                                            required property var modelData
                                            width: row.width
                                            spacing: 4
                                            bottomPadding: 8
                                            Label {
                                                text: "Psalm " + modelData.number
                                                color: psalter.gold
                                                font.pixelSize: 12
                                            }
                                            Label {
                                                width: parent.width
                                                visible: modelData.superscription
                                                text: modelData.superscription || ""
                                                color: psalter.muted
                                                font.italic: true
                                                font.family: psalter.face()
                                                font.pixelSize: 12
                                                wrapMode: Text.WordWrap
                                            }
                                            Repeater {
                                                model: modelData.verses || []
                                                delegate: Label {
                                                    required property var modelData
                                                    width: row.width
                                                    text: modelData.number + "  " + modelData.text
                                                    color: psalter.parchment
                                                    font.family: psalter.face()
                                                    font.pixelSize: 12
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }
                                    }
                                    Item {
                                        objectName: "psalter-end-" + row.modelData.number
                                        property int kathisma: row.modelData.number
                                        width: 1
                                        height: 1
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width - 48; height: 1; color: psalter.line }
                Label {
                    objectName: "psalter-source"
                    width: parent.width - 48
                    text: bridge.psalterSource
                    color: psalter.faint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    topPadding: 8
                }
            }
            EdgeFade {
                y: reader.contentY
                width: reader.width
                height: reader.height
                z: 8
            }
        }
    }
}
