import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: library
    objectName: "library"
    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"
    property bool cautionClosed: false

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }
    function face() { return charter.status === FontLoader.Ready ? charter.name : "serif" }

    Component.onCompleted: bridge.showLibrary("")

    Flickable {
        id: libraryScroll
        objectName: "library-scroll"
        anchors.fill: parent
        visible: bridge.editorPage.open !== true && !(bridge.editorPage.caution === true && !library.cautionClosed)
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: parent.width
            spacing: 0

            TextField {
                objectName: "library-search"
                width: parent.width - 48
                x: 24
                topPadding: 16
                placeholderText: "Search by title"
                color: library.parchment
                placeholderTextColor: library.faint
                font.pixelSize: 14
                background: Rectangle { color: "#1c1e26"; radius: 5 }
                onTextChanged: bridge.showLibrary(text)
            }

            Label {
                width: parent.width - 48
                x: 24
                text: bridge.libraryPage.intro || ""
                color: library.faint
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                topPadding: 12
                bottomPadding: 4
            }

            Repeater {
                model: bridge.libraryPage.groups || []
                delegate: Column {
                    required property var modelData
                    width: column.width
                    spacing: 0
                    Label {
                        x: 24
                        width: parent.width - 48
                        text: modelData.category
                        color: library.gold
                        font.pixelSize: 13
                        topPadding: 14
                        bottomPadding: 4
                    }
                    Repeater {
                        model: modelData.templates || []
                        delegate: Item {
                            id: row
                            required property var modelData
                            width: column.width - 48
                            x: 24
                            height: body.implicitHeight + 16
                            Column {
                                id: body
                                y: 8
                                width: parent.width - 96
                                spacing: 2
                                Label {
                                    width: parent.width
                                    text: row.modelData.title
                                    color: row.modelData.taken ? library.muted : library.parchment
                                    font.pixelSize: 15
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    width: parent.width
                                    text: row.modelData.summary
                                    color: library.faint
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    width: parent.width
                                    visible: (row.modelData.observanceNote || "").length > 0
                                    text: row.modelData.observanceNote || ""
                                    color: library.gold
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    width: parent.width
                                    visible: (row.modelData.note || "").length > 0
                                    text: row.modelData.note || ""
                                    color: library.faint
                                    font.pixelSize: 13
                                    font.italic: true
                                    wrapMode: Text.WordWrap
                                }
                                Flow {
                                    width: parent.width
                                    spacing: 10
                                    visible: (row.modelData.terms || []).length > 0
                                    Repeater {
                                        model: row.modelData.terms || []
                                        delegate: Item {
                                            required property var modelData
                                            width: chipLabel.implicitWidth + 8
                                            height: chipLabel.implicitHeight + 4
                                            Label {
                                                id: chipLabel
                                                anchors.centerIn: parent
                                                text: modelData.term
                                                color: library.gold
                                                font.pixelSize: 12
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: window.openGlossary(modelData.slug)
                                            }
                                        }
                                    }
                                }
                            }
                            Label {
                                objectName: row.modelData.taken
                                            ? ("library-edit-" + row.modelData.id)
                                            : ("library-take-" + row.modelData.id)
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                text: row.modelData.taken ? "Edit" : "Take on"
                                color: library.gold
                                font.pixelSize: 13
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: row.modelData.taken
                                               ? bridge.openEditor(row.modelData.ruleID || "")
                                               : bridge.prepareTemplate(row.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: column.width
                visible: (bridge.libraryPage.custom || []).length > 0
                spacing: 0
                Label {
                    x: 24
                    width: parent.width - 48
                    text: "Custom"
                    color: library.gold
                    font.pixelSize: 13
                    topPadding: 14
                    bottomPadding: 4
                }
                Label {
                    x: 24
                    width: parent.width - 48
                    text: bridge.libraryPage.customNote || ""
                    color: library.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    bottomPadding: 4
                }
                Repeater {
                    model: bridge.libraryPage.custom || []
                    delegate: Item {
                        id: custom
                        required property var modelData
                        width: column.width - 48
                        x: 24
                        height: customBody.implicitHeight + 16
                        Column {
                            id: customBody
                            y: 8
                            width: parent.width - 150
                            spacing: 2
                            Label {
                                text: custom.modelData.title
                                color: custom.modelData.active ? library.muted : library.parchment
                                font.pixelSize: 15
                            }
                            Label {
                                text: custom.modelData.time
                                color: library.faint
                                font.pixelSize: 13
                            }
                            Label {
                                visible: (custom.modelData.attribution || "").length > 0
                                text: custom.modelData.attribution || ""
                                color: library.gold
                                font.pixelSize: 11
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            spacing: 10
                            Label {
                                text: custom.modelData.active ? "Edit" : "Take on"
                                color: library.gold
                                font.pixelSize: 13
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: custom.modelData.active
                                               ? bridge.openEditor(custom.modelData.id)
                                               : bridge.takeUp(custom.modelData.id)
                                }
                            }
                            Label {
                                text: "×"
                                color: library.faint
                                font.pixelSize: 13
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: bridge.setAside(custom.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Label {
                objectName: "library-write-own"
                x: 24
                text: "Write your own rule"
                color: library.gold
                font.pixelSize: 15
                topPadding: 16
                bottomPadding: 18
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        library.cautionClosed = false
                        bridge.openEditor("")
                    }
                }
            }
        }
        EdgeFade {
            y: libraryScroll.contentY
            width: libraryScroll.width
            height: libraryScroll.height
            z: 8
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 24
        visible: bridge.editorPage.caution === true && !library.cautionClosed && bridge.editorPage.open !== true
        spacing: 14
        Label {
            text: "Writing Your Own Rule"
            color: library.parchment
            font.family: library.face()
            font.pixelSize: 23
        }
        Label {
            objectName: "library-caution"
            width: parent.width
            text: bridge.editorPage.cautionText || ""
            color: library.parchment
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }
        CheckBox {
            id: hideCaution
            objectName: "library-caution-hide"
            text: "Don't Show Again"
            contentItem: Label { text: hideCaution.text; color: library.parchment; font.pixelSize: 14 }
        }
        Row {
            spacing: 16
            Label {
                objectName: "library-caution-cancel"
                text: "Cancel"
                color: library.muted
                font.pixelSize: 14
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: library.cautionClosed = true }
            }
            Label {
                objectName: "library-caution-accept"
                text: "I Understand"
                color: library.gold
                font.pixelSize: 14
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: bridge.acknowledgeCaution(hideCaution.checked)
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: bridge.editorPage.open === true
        visible: active
        source: "Editor.qml"
    }
}
