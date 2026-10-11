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

                ComboBox {
                    id: churchBox
                    objectName: "welcome-church"
                    width: parent.width
                    height: 40
                    model: welcome.churchKey.length > 0 ? welcome.churchKey.split("\n") : []
                    font.pixelSize: 15
                    onActivated: function(index) {
                        welcome.chosen = index === 0 ? "" : churchBox.textAt(index)
                    }

                    contentItem: Label {
                        leftPadding: 12
                        rightPadding: 28
                        text: churchBox.displayText
                        color: welcome.parchment
                        font.pixelSize: 15
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: "transparent"
                        border.color: welcome.line
                        radius: 6
                    }
                    indicator: Label {
                        x: churchBox.width - width - 12
                        y: (churchBox.height - implicitHeight) / 2
                        text: "\u25BE"
                        color: welcome.gold
                        font.pixelSize: 12
                    }

                    delegate: ItemDelegate {
                        id: churchChoice
                        required property int index
                        required property var modelData
                        width: churchBox.width
                        height: 36
                        objectName: index === 0 ? "welcome-church-none" : ("welcome-church-" + modelData)
                        highlighted: churchBox.highlightedIndex === index
                        contentItem: Label {
                            text: churchChoice.modelData
                            color: churchChoice.highlighted ? welcome.gold : welcome.parchment
                            font.pixelSize: 14
                            leftPadding: 12
                            rightPadding: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            color: churchChoice.highlighted ? "#2a261c" : "#1c1e26"
                        }
                    }

                    popup: Popup {
                        objectName: "welcome-church-popup"
                        y: churchBox.height + 4
                        width: churchBox.width
                        padding: 1
                        implicitHeight: Math.min(churchList.contentHeight + 2, 6 * 36 + 2)
                        contentItem: ListView {
                            id: churchList
                            objectName: "welcome-church-list"
                            clip: true
                            implicitHeight: contentHeight
                            model: churchBox.popup.visible ? churchBox.delegateModel : null
                            currentIndex: churchBox.highlightedIndex
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                background: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: "#2e2a20"
                                }
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: welcome.gold
                                    opacity: 0.9
                                }
                            }
                        }
                        background: Rectangle {
                            color: "#1c1e26"
                            border.color: welcome.line
                            radius: 6
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

    readonly property string churchKey: {
        const none = bridge.settings.noChurch || ""
        const rest = bridge.settings.churches || []
        let key = none
        for (let index = 0; index < rest.length; index++) key += "\n" + rest[index]
        return key
    }
}
