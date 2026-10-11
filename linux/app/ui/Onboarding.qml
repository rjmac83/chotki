import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: welcome
    objectName: "welcome"
    width: parent ? parent.width : 800
    height: parent ? parent.height : 700

    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"
    property string chosen: ""

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }

    function spanText(paragraph) {
        const spans = paragraph.spans || []
        let whole = ""
        for (let index = 0; index < spans.length; index++) whole += spans[index].text || ""
        return whole
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Flickable {
            id: scroller
            objectName: "welcome-scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: page.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            WheelHandler {
                onWheel: function(event) {
                    const pixels = event.pixelDelta.y
                    const angle = event.angleDelta.y
                    const delta = pixels !== 0 ? pixels : angle
                    if (!delta) return
                    const limit = Math.max(0, scroller.contentHeight - scroller.height)
                    scroller.contentY = Math.max(0, Math.min(limit, scroller.contentY - delta))
                    event.accepted = true
                }
            }

            Column {
                id: page
                width: Math.min(560, scroller.width - 44)
                x: Math.max(0, (scroller.width - width) / 2)
                spacing: 14
                topPadding: 28
                bottomPadding: 28

                Label {
                    objectName: "welcome-title"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: bridge.settings.welcomeTitle || ""
                    color: welcome.parchment
                    font.family: charter.name
                    font.pixelSize: 26
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: bridge.settings.welcomeParagraphs || []
                    delegate: Item {
                        required property var modelData
                        width: page.width
                        height: body.implicitHeight
                        Rectangle {
                            visible: modelData.aside === true
                            width: 2
                            height: parent.height
                            color: welcome.line
                        }
                        Text {
                            id: body
                            x: modelData.aside === true ? 12 : 0
                            width: parent.width - x
                            text: welcome.spanText(modelData)
                            color: modelData.aside === true ? welcome.faint : welcome.parchment
                            font.italic: modelData.aside === true
                            font.family: charter.name
                            font.pixelSize: modelData.aside === true ? 13 : 16
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "What should we call you?"
                    color: welcome.parchment
                    font.family: charter.name
                    font.pixelSize: 26
                    wrapMode: Text.WordWrap
                    topPadding: 8
                }
                TextField {
                    id: nameField
                    objectName: "welcome-name"
                    width: parent.width
                    height: 40
                    placeholderText: "First name or Baptismal name."
                    color: welcome.parchment
                    placeholderTextColor: welcome.faint
                    font.pixelSize: 16
                    selectByMouse: true
                    background: Rectangle { color: "transparent"; border.color: welcome.line; radius: 6 }
                }
                Label {
                    objectName: "welcome-church-prompt"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: bridge.settings.churchPrompt || ""
                    color: welcome.parchment
                    font.family: charter.name
                    font.pixelSize: 22
                    wrapMode: Text.WordWrap
                    topPadding: 8
                }

                // Rows are placed by hand. A Column delivers every click to the last row.
                Item {
                    id: churches
                    width: parent.width
                    height: churchRepeater.count * 28
                    Repeater {
                        id: churchRepeater
                        model: welcome.choices()
                        delegate: Item {
                            required property int index
                            required property var modelData
                            objectName: index === 0 ? "welcome-church-none" : ("welcome-church-" + modelData)
                            y: index * 28
                            width: churches.width
                            height: 28
                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16
                                text: modelData
                                color: welcome.chosen === (index === 0 ? "" : modelData) ? welcome.gold : welcome.parchment
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                preventStealing: true
                                onClicked: welcome.chosen = index === 0 ? "" : modelData
                            }
                        }
                    }
                }

                Item {
                    objectName: "welcome-continue"
                    width: parent.width
                    height: 40
                    Rectangle { anchors.fill: parent; color: "#2a261c"; radius: 8; border.color: welcome.gold }
                    Label {
                        anchors.centerIn: parent
                        text: bridge.settings.beginLabel || ""
                        color: welcome.gold
                        font.pixelSize: 15
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({
                            welcome: true,
                            name: nameField.text || "",
                            church: welcome.chosen
                        })
                    }
                }
            }
        }
    }

    function choices() {
        const none = bridge.settings.noChurch || ""
        const rest = bridge.settings.churches || []
        const rows = [none]
        for (let index = 0; index < rest.length; index++) rows.push(rest[index])
        return rows
    }
}
