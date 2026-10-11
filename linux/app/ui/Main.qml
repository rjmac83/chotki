import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1100
    height: 860
    minimumWidth: 620
    minimumHeight: 540
    visible: true
    title: "Chotki"
    color: "#15161c"

    readonly property color ground: "#15161c"
    readonly property color panel: "#1c1e26"
    readonly property color parchment: "#e8dfcd"
    readonly property color parchmentDim: "#d8cfbd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color goldDim: "#a88a33"
    readonly property color line: "#2e2a20"
    readonly property color lineSoft: "#23252c"
    readonly property color violet: "#9a8fc4"
    readonly property color ochre: "#a63a38"
    property bool sidebarCollapsed: false
    property string section: "Home"
    property bool welcomeAsked: false
    property string glossaryReturn: "Home"
    property string glossaryPending: ""
    property bool openingPlayed: false
    property int openingStarts: 0
    property int heardEvent: -1
    property bool openPsalter: false
    property string watchedDate: bridge.selectedDate || ""
    property int heardThanks: -1
    property int heardRecord: -1
    property bool autostartSynced: false
    onWatchedDateChanged: window.dismissThanks()

    function notePrayer() {
        if (bridge.prayerEvent > heardEvent && bridge.prayerSound.length > 0) {
            heardEvent = bridge.prayerEvent
            bridge.playSound(bridge.prayerSound)
        } else if (bridge.prayerEvent < heardEvent) {
            heardEvent = bridge.prayerEvent
        }
    }

    function noteThanks() {
        const event = bridge.thanksEvent
        if (event === undefined || event === null || event === heardThanks) return
        heardThanks = event
        const line = bridge.thanksgiving || ""
        if (!line.length) return
        thanksLabel.text = line
        thanksLabel.opacity = 1
        thanksFade.restart()
    }

    function dismissThanks() {
        thanksFade.stop()
        thanksLabel.opacity = 0
    }

    function welcoming() {
        return bridge.needsWelcome === true
    }

    function ensureWelcome() {
        if (!welcoming() || welcomeAsked) return
        welcomeAsked = true
        bridge.showSettings()
    }

    function openGlossary(slug) {
        if (welcoming()) return
        if (section !== "Glossary") glossaryReturn = section
        glossaryPending = slug || ""
        section = "Glossary"
        if (glossaryLoader.item) glossaryLoader.item.present(glossaryPending)
    }

    function closeGlossary() {
        section = glossaryReturn || "Home"
    }

    function showSection(name) {
        if (welcoming()) return
        if (name === "Glossary") {
            openGlossary("")
            return
        }
        if (name === "Prayers") {
            openPsalter = false
            section = "Prayers"
            if (prayersLoader.item) prayersLoader.item.psalterOpen = false
            return
        }
        if (name === "Reading") {
            openPsalter = false
            section = "Reading"
            bridge.showReading()
            return
        }
        section = name
    }

    function openCard(destination, selection, band, ruleID) {
        if (welcoming()) return
        if (!destination || destination === "fast") return
        if (destination === "rope" || destination === "prayers") {
            openPsalter = false
            bridge.choosePrayer(selection || "")
            section = "Prayers"
            if (prayersLoader.item) prayersLoader.item.psalterOpen = false
            return
        }
        if (destination === "reading") {
            openPsalter = false
            section = "Reading"
            const named = band === undefined || band === null ? -1 : band
            bridge.openReading(named)
            return
        }
        if (destination === "psalter") {
            openPsalter = true
            section = "Prayers"
            if (prayersLoader.item) prayersLoader.item.psalterOpen = true
            return
        }
        if (destination === "editor") {
            bridge.openEditor(ruleID || "")
            section = "Library"
        }
    }

    function maybeOpen() {
        if (!playOpening || openingPlayed || !bridge.openingReady) return
        openingPlayed = true
        openingStarts += 1
        openingLoader.active = true
    }
    readonly property var groups: [
        { heading: "The Day", items: ["Home"] },
        { heading: "To Read", items: ["Prayers", "Reading"] },
        { heading: "The Record", items: ["Progress", "Library"] },
        { heading: "Reference", items: ["Glossary", "Settings"] }
    ]

    Shortcut { sequence: "Ctrl+1"; onActivated: if (!window.welcoming()) window.section = "Home" }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.showSection("Prayers") }
    Shortcut { sequence: "Ctrl+3"; onActivated: window.showSection("Reading") }
    Shortcut { sequence: "Ctrl+4"; onActivated: window.showSection("Progress") }
    Shortcut { sequence: "Ctrl+5"; onActivated: if (!window.welcoming()) window.section = "Library" }
    Shortcut { sequence: "Ctrl+6"; onActivated: window.showSection("Glossary") }
    Shortcut { sequence: "Ctrl+7"; onActivated: window.showSection("Settings") }
    Shortcut {
        sequence: "Ctrl+Shift+S"
        onActivated: window.sidebarCollapsed = !window.sidebarCollapsed
    }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

    Timer {
        id: reminderClock
        interval: 30000
        repeat: true
        running: bridge.connected === true && bridge.review !== true
        onTriggered: if (bridge.tickReminders) bridge.tickReminders()
    }
    Timer {
        id: reminderNudge
        interval: 30
        onTriggered: if (bridge.tickReminders && bridge.review !== true) bridge.tickReminders()
    }

    function noteSession() {
        if (bridge.review === true || autostartSynced || bridge.connected !== true) return
        if (!bridge.syncAutostart) return
        autostartSynced = true
        bridge.syncAutostart()
    }

    function noteRecord() {
        if (bridge.review === true) return
        const touch = bridge.recordTouch
        if (touch === undefined || touch === null || touch === heardRecord) return
        heardRecord = touch
        reminderNudge.restart()
    }

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }
    FontLoader { id: charterBold; source: "fonts/XCharter-Bold.otf" }

    function greeting() {
        const hour = new Date().getHours()
        const opening = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return opening + (bridge.displayName.length ? ", " + bridge.displayName : "")
    }

    function dayLabel() {
        if (!bridge.today.length) return ""
        const date = new Date(bridge.today + "T12:00:00")
        return Qt.formatDate(date, "dddd d MMMM")
    }

    Canvas {
        id: backdrop
        anchors.fill: parent
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        canvasSize: Qt.size(width * dpr, height * dpr)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onDprChanged: requestPaint()
        onPaint: {
            const context = getContext("2d")
            if (context.reset) context.reset()
            context.setTransform(dpr, 0, 0, dpr, 0, 0)
            context.fillStyle = window.ground
            context.fillRect(0, 0, width, height)
            const parchment = context.createRadialGradient(0, 0, 0, 0, 0, width * 0.7)
            parchment.addColorStop(0, "rgba(232, 223, 205, 0.14)")
            parchment.addColorStop(1, "rgba(232, 223, 205, 0)")
            context.fillStyle = parchment
            context.fillRect(0, 0, width, height)
            const gold = context.createRadialGradient(width, height, 0, width, height, width * 0.6)
            gold.addColorStop(0, "rgba(201, 162, 39, 0.10)")
            gold.addColorStop(1, "rgba(201, 162, 39, 0)")
            context.fillStyle = gold
            context.fillRect(0, 0, width, height)
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: window.sidebarCollapsed ? 58 : 188
            color: Qt.rgba(0.082, 0.086, 0.110, 0.24)

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 3

                Item {
                    objectName: "sidebar-collapse"
                    width: parent.width
                    height: 32
                    Accessible.name: window.sidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar"
                    Label {
                        x: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▣"
                        color: window.muted
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: window.sidebarCollapsed = !window.sidebarCollapsed
                    }
                }

                Repeater {
                    model: window.groups
                    delegate: Column {
                        required property var modelData
                        width: window.sidebarCollapsed ? 38 : 168
                        spacing: 3

                        Label {
                            visible: !window.sidebarCollapsed
                            text: modelData.heading
                            color: window.muted
                            opacity: 0.92
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            leftPadding: 10
                            topPadding: 12
                            bottomPadding: 4
                        }
                        Item {
                            visible: window.sidebarCollapsed
                            width: 1
                            height: 12
                        }

                        Repeater {
                            model: modelData.items
                            delegate: Rectangle {
                                required property string modelData
                                objectName: "nav-" + modelData
                                width: window.sidebarCollapsed ? 38 : 168
                                height: 36
                                color: window.section === modelData ? window.panel : "transparent"
                                radius: 8
                                Accessible.name: modelData
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    Icon {
                                        kind: modelData
                                        width: 18
                                        height: 18
                                        tint: window.section === modelData ? window.parchment : window.muted
                                    }
                                    Label {
                                        visible: !window.sidebarCollapsed
                                        text: modelData
                                        color: window.section === modelData ? window.parchment : window.muted
                                        font.pixelSize: 13
                                        font.weight: window.section === modelData ? Font.Medium : Font.Normal
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: window.showSection(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: window.lineSoft
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.topMargin: 24
                anchors.bottomMargin: 18
                spacing: 0

                RowLayout {
                    // The welcome page already carries the title from core.
                    visible: !window.welcoming()
                    Layout.fillWidth: true
                    Label {
                        objectName: "page-title"
                        text: window.section === "Home" ? window.greeting() : window.section
                        color: window.parchment
                        font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        Layout.bottomMargin: 18
                    }
                    Label {
                        visible: bridge.review
                        text: "REVIEW"
                        color: window.gold
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        rightPadding: 5
                    }
                }

                Loader {
                    id: welcomeLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: window.welcoming()
                    visible: active
                    source: "Onboarding.qml"
                }
                Loader {
                    id: homeLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Home"
                    visible: active
                    source: "Home.qml"
                }
                Connections {
                    target: homeLoader.item
                    function onLibraryRequested() { window.section = "Library" }
                    function onCardRequested(destination, selection, band, ruleID) {
                        window.openCard(destination, selection, band, ruleID)
                    }
                }

                Loader {
                    id: prayersLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Prayers"
                    visible: active
                    source: "Prayers.qml"
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Reading"
                    visible: active
                    source: "Reading.qml"
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Library"
                    visible: active
                    source: "Library.qml"
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Progress"
                    visible: active
                    source: "Progress.qml"
                }
                Loader {
                    id: glossaryLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Glossary"
                    visible: active
                    source: "Glossary.qml"
                }
                Loader {
                    id: settingsLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: active
                    active: !window.welcoming() && window.section === "Settings"
                    visible: active
                    source: "Settings.qml"
                }

                ColumnLayout {
                    visible: !window.welcoming()
                            && window.section !== "Home" && window.section !== "Prayers"
                            && window.section !== "Reading" && window.section !== "Library"
                            && window.section !== "Progress" && window.section !== "Glossary"
                            && window.section !== "Settings"
                    Layout.fillWidth: true
                    Layout.fillHeight: visible
                    Item { height: 46 }
                    Label {
                        text: window.section
                        color: window.parchment
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Item { height: 18 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: window.lineSoft }
                    Item { height: 24 }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 196
                        color: window.panel
                        radius: 18
                        border.color: "#343237"
                        Column {
                            anchors.centerIn: parent
                            spacing: 9
                            Label {
                                text: window.section
                                color: window.parchment
                                font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                                font.pixelSize: 24
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label {
                                text: "This section is part of the desktop layout."
                                color: window.muted
                                font.pixelSize: 13
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                Label {
                    visible: !bridge.connected
                    text: bridge.status
                    color: window.gold
                    font.pixelSize: 12
                }
                Label {
                    visible: bridge.error.length > 0
                    text: bridge.error
                    color: "#d9a396"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    Connections {
        target: bridge
        function onChanged() {
            window.notePrayer()
            window.maybeOpen()
            window.noteThanks()
            window.ensureWelcome()
            window.noteSession()
            window.noteRecord()
        }
    }

    Item {
        id: reminderBanner
        objectName: "reminder-banner"
        z: 25
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: window.sidebarCollapsed ? 58 : 188
        anchors.rightMargin: 12
        anchors.bottomMargin: 12
        visible: notices.length > 0
        height: visible ? notices.length * 56 : 0
        property var notices: {
            const list = bridge.reminders
            if (!list || !list.length) return []
            return list
        }

        Repeater {
            model: reminderBanner.notices
            delegate: Item {
                id: notice
                property var noticeData: modelData
                y: index * 56
                width: reminderBanner.width
                height: 56
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: window.panel
                    border.color: window.line
                }
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: actionsRow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: (notice.noticeData.title || "")
                          + (notice.noticeData.body ? "\n" + notice.noticeData.body : "")
                    color: window.parchment
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
                Row {
                    id: actionsRow
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Repeater {
                        model: notice.noticeData.actions || []
                        delegate: Item {
                            property var actionData: modelData
                            width: Math.max(32, actionText.implicitWidth + 16)
                            height: 32
                            Label {
                                id: actionText
                                anchors.centerIn: parent
                                text: actionData.title || ""
                                color: window.gold
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                objectName: "reminder-action-" + (actionData.id || "")
                                onClicked: {
                                    if (bridge.notificationAction)
                                        bridge.notificationAction(notice.noticeData.id, actionData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Label {
        id: thanksLabel
        objectName: "thanksgiving"
        z: 30
        anchors.horizontalCenter: parent.horizontalCenter
        y: 72
        opacity: 0
        visible: opacity > 0
        text: ""
        color: window.parchment
        font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
        font.pixelSize: 18
        SequentialAnimation {
            id: thanksFade
            PauseAnimation { duration: 6000 }
            NumberAnimation { target: thanksLabel; property: "opacity"; to: 0; duration: 700 }
        }
    }

    Loader {
        id: openingLoader
        anchors.fill: parent
        z: 40
        active: false
        visible: active
        source: "OpeningMark.qml"
        onLoaded: item.finished.connect(function() {
            Qt.callLater(function() { openingLoader.active = false })
        })
    }

    Component.onCompleted: {
        ensureWelcome()
        maybeOpen()
        noteSession()
    }
}
