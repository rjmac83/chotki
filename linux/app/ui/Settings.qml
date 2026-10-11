import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: settings
    objectName: "settings"
    width: parent ? parent.width : 800
    height: parent ? parent.height : 700

    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"
    readonly property var page: bridge.settings || ({})

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }

    function syncFields() {
        if (!nameField.activeFocus) nameField.text = page.displayName || ""
        if (!fatherField.activeFocus) fatherField.text = page.spiritualFatherName || ""
    }

    Connections {
        target: bridge
        function onChanged() { settings.syncFields() }
    }

    Component.onCompleted: {
        bridge.showSettings()
        syncFields()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Flickable {
            id: scroller
            objectName: "settings-scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: column.implicitHeight
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
                id: column
                width: Math.min(720, scroller.width - 28)
                x: 14
                spacing: 0
                bottomPadding: 24

                Label { text: "You"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                Label { text: "My Name"; color: settings.muted; font.pixelSize: 12; bottomPadding: 4 }
                TextField {
                    id: nameField
                    objectName: "settings-name"
                    width: parent.width
                    height: 36
                    placeholderText: "First name or Baptismal name"
                    color: settings.parchment
                    placeholderTextColor: settings.faint
                    font.pixelSize: 14
                    selectByMouse: true
                    background: Rectangle { color: "transparent"; border.color: settings.line; radius: 6 }
                    onEditingFinished: bridge.saveSettings({ name: text || "" })
                }
                Label { text: "My Spiritual Father's Name"; color: settings.muted; font.pixelSize: 12; topPadding: 10; bottomPadding: 4 }
                TextField {
                    id: fatherField
                    objectName: "settings-father"
                    width: parent.width
                    height: 36
                    placeholderText: "Name"
                    color: settings.parchment
                    placeholderTextColor: settings.faint
                    font.pixelSize: 14
                    selectByMouse: true
                    background: Rectangle { color: "transparent"; border.color: settings.line; radius: 6 }
                    onEditingFinished: bridge.saveSettings({ father: text || "" })
                }
                Item {
                    objectName: "settings-clear-father"
                    width: clearLabel.implicitWidth + 12
                    height: 28
                    enabled: (settings.page.spiritualFatherName || "").length > 0
                    Label {
                        id: clearLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear"
                        color: parent.enabled ? settings.gold : settings.faint
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.enabled
                        onClicked: bridge.saveSettings({ father: "" })
                    }
                }

                Label { text: "Your Church"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                Item {
                    id: churches
                    width: parent.width
                    height: churchRepeater.count * 28
                    Repeater {
                        id: churchRepeater
                        model: settings.churchChoices()
                        delegate: Item {
                            required property int index
                            required property var modelData
                            objectName: index === 0 ? "settings-church-none" : ("settings-church-" + modelData)
                            y: index * 28
                            width: churches.width
                            height: 28
                            readonly property bool selected: index === 0
                                    ? (settings.page.church || "") === ""
                                    : settings.page.church === modelData
                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16
                                text: modelData
                                color: parent.selected ? settings.gold : settings.parchment
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                preventStealing: true
                                onClicked: bridge.saveSettings({ church: index === 0 ? "" : modelData })
                            }
                        }
                    }
                }
                Repeater {
                    model: settings.page.reckonings || []
                    delegate: Item {
                        required property var modelData
                        objectName: "settings-reckoning-" + modelData.value
                        width: parent.width
                        height: 28
                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: settings.page.reckoning === modelData.value ? settings.gold : settings.parchment
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: bridge.saveSettings({ reckoning: modelData.value })
                        }
                    }
                }
                Label {
                    objectName: "settings-calendar-note"
                    width: parent.width
                    visible: (settings.page.calendarNote || "").length > 0
                    text: settings.page.calendarNote || ""
                    color: settings.gold
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    topPadding: 6
                }
                Label {
                    objectName: "settings-akathist"
                    width: parent.width
                    visible: (settings.page.akathistNote || "").length > 0
                    text: settings.page.akathistNote || ""
                    color: settings.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    topPadding: 6
                }
                Repeater {
                    model: settings.page.practiceNotes || []
                    delegate: Label {
                        required property var modelData
                        width: column.width
                        text: modelData
                        color: settings.faint
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        topPadding: 4
                    }
                }

                Label { text: "The Calendar"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                Label { text: "Fasting"; color: settings.parchment; font.pixelSize: 14 }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: settings.page.observances || []
                        delegate: Item {
                            required property var modelData
                            objectName: "settings-fasting-" + modelData.value
                            width: fastingLabel.implicitWidth + 16
                            height: 28
                            Label {
                                id: fastingLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: settings.page.fasting === modelData.value ? settings.gold : settings.muted
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: bridge.saveSettings({ fasting: modelData.value })
                            }
                        }
                    }
                }
                Label { text: "Feasts"; color: settings.parchment; font.pixelSize: 14; topPadding: 6 }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: settings.page.observances || []
                        delegate: Item {
                            required property var modelData
                            objectName: "settings-feasts-" + modelData.value
                            width: feastLabel.implicitWidth + 16
                            height: 28
                            Label {
                                id: feastLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: settings.page.feasts === modelData.value ? settings.gold : settings.muted
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: bridge.saveSettings({ feasts: modelData.value })
                            }
                        }
                    }
                }
                Item {
                    objectName: "settings-old-style"
                    width: parent.width
                    height: 44
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Show old-style dates"
                        color: settings.parchment
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.page.showOldStyleDates === true ? "On" : "Off"
                        color: settings.page.showOldStyleDates === true ? settings.gold : settings.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({ showOldStyleDates: settings.page.showOldStyleDates !== true })
                    }
                }
                Label {
                    width: parent.width
                    text: settings.page.oldStyleHelp || ""
                    color: settings.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Label { text: "Clock"; color: settings.parchment; font.pixelSize: 14; topPadding: 8 }
                Repeater {
                    model: settings.page.clocks || []
                    delegate: Item {
                        required property var modelData
                        objectName: "settings-clock-" + modelData.value
                        width: parent.width
                        height: 28
                        Label {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: settings.page.clock === modelData.value ? settings.gold : settings.parchment
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: bridge.saveSettings({ clock: modelData.value })
                        }
                    }
                }

                Label { text: "Reminders"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                Item {
                    objectName: "settings-notifications"
                    width: parent.width
                    height: 36
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications"
                        color: settings.parchment
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.page.notifications === true ? "On" : "Off"
                        color: settings.page.notifications === true ? settings.gold : settings.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({ notifications: settings.page.notifications !== true })
                    }
                }
                Label {
                    width: parent.width
                    text: settings.page.notificationHelp || ""
                    color: settings.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Label {
                    text: "Warn me"
                    color: settings.page.notifications === true ? settings.parchment : settings.faint
                    font.pixelSize: 14
                    topPadding: 6
                }
                Repeater {
                    model: settings.page.leads || []
                    delegate: Item {
                        required property var modelData
                        objectName: "settings-lead-" + modelData.value
                        width: parent.width
                        height: 28
                        enabled: settings.page.notifications === true
                        opacity: enabled ? 1 : 0.45
                        Label {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: String(settings.page.lead) === String(modelData.value) ? settings.gold : settings.parchment
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.enabled
                            onClicked: bridge.saveSettings({ lead: Number(modelData.value) })
                        }
                    }
                }

                Label { text: "Prayer Rope"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                Item {
                    objectName: "settings-chime"
                    width: parent.width
                    height: 36
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Chime when a knot is complete"
                        color: settings.parchment
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.page.chime === true ? "On" : "Off"
                        color: settings.page.chime === true ? settings.gold : settings.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({ chime: settings.page.chime !== true })
                    }
                }
                Item {
                    objectName: "settings-tick"
                    width: parent.width
                    height: 36
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Click on each knot"
                        color: settings.parchment
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.page.tick === true ? "On" : "Off"
                        color: settings.page.tick === true ? settings.gold : settings.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({ tick: settings.page.tick !== true })
                    }
                }
                Label {
                    width: parent.width
                    text: settings.page.tickHelp || ""
                    color: settings.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Label { text: "Your Record"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                TextField {
                    id: backupPath
                    objectName: "settings-backup-path"
                    width: parent.width
                    height: 36
                    placeholderText: "Absolute path to a .json backup"
                    color: settings.parchment
                    placeholderTextColor: settings.faint
                    font.pixelSize: 14
                    selectByMouse: true
                    background: Rectangle { color: "transparent"; border.color: settings.line; radius: 6 }
                }
                Item {
                    objectName: "settings-export"
                    width: parent.width
                    height: 32
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Export a backup\u2026"
                        color: settings.gold
                        font.pixelSize: 14
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.exportBackup(backupPath.text || "")
                    }
                }
                Item {
                    objectName: "settings-restore"
                    width: parent.width
                    height: 32
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Restore from a backup\u2026"
                        color: settings.gold
                        font.pixelSize: 14
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.importBackup(backupPath.text || "")
                    }
                }
                Label {
                    width: parent.width
                    text: settings.page.backupHelp || ""
                    color: settings.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Label {
                    objectName: "settings-backup-directory"
                    width: parent.width
                    text: settings.page.backupDirectory || ""
                    color: settings.muted
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    topPadding: 4
                }

                Label { text: "General"; color: settings.muted; font.pixelSize: 13; topPadding: 14; bottomPadding: 4 }
                Item {
                    objectName: "settings-figure"
                    width: parent.width
                    height: 36
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Show the consistency figure"
                        color: settings.parchment
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.page.showFigure === true ? "On" : "Off"
                        color: settings.page.showFigure === true ? settings.gold : settings.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({ showFigure: settings.page.showFigure !== true })
                    }
                }
                Label {
                    width: parent.width
                    text: settings.page.figureHelp || ""
                    color: settings.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Item {
                    objectName: "settings-motion"
                    width: parent.width
                    height: 36
                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Reduced motion"
                        color: settings.parchment
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: bridge.reducedMotion === true ? "On" : "Off"
                        color: bridge.reducedMotion === true ? settings.gold : settings.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.saveSettings({ motion: bridge.reducedMotion !== true })
                    }
                }
                Item {
                    width: parent.width
                    height: 28
                    Item {
                        objectName: "settings-about"
                        width: aboutLabel.implicitWidth + 8
                        height: 28
                        x: Math.max(0, (parent.width - width - privacy.width - 18) / 2)
                        Label {
                            id: aboutLabel
                            anchors.centerIn: parent
                            text: "About Chotki"
                            color: settings.faint
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Qt.openUrlExternally(settings.page.aboutURL || "")
                        }
                    }
                    Item {
                        id: privacy
                        objectName: "settings-privacy"
                        width: privacyLabel.implicitWidth + 8
                        height: 28
                        anchors.left: parent.left
                        anchors.leftMargin: (parent.width + aboutLabel.implicitWidth) / 2 + 8
                        Label {
                            id: privacyLabel
                            anchors.centerIn: parent
                            text: "Privacy"
                            color: settings.faint
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Qt.openUrlExternally(settings.page.privacyURL || "")
                        }
                    }
                }
                Label {
                    objectName: "settings-version"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: settings.page.version || ""
                    color: settings.faint
                    font.pixelSize: 12
                    topPadding: 8
                }
                Label {
                    objectName: "settings-notice"
                    width: parent.width
                    visible: (settings.page.notice || "").length > 0
                    text: settings.page.notice || ""
                    color: settings.gold
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    topPadding: 8
                }
            }
        }
    }

    function churchChoices() {
        const none = page.noChurch || ""
        const rest = page.churches || []
        const rows = []
        if (none.length) rows.push(none)
        for (let index = 0; index < rest.length; index++) rows.push(rest[index])
        return rows
    }
}
