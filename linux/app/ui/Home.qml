import QtQuick
import QtQuick.Controls
import ChotkiArtwork 1.0

Item {
    id: home
    objectName: "home"
    signal libraryRequested()
    signal cardRequested(string destination, string selection, int band, string ruleID)
    width: parent ? parent.width : 850
    height: parent ? parent.height : 700

    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color gold: "#c9a227"
    readonly property color ink: "#1a1916"
    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }

    function localDate(iso) {
        return iso.length ? new Date(iso + "T12:00:00") : new Date()
    }
    function monthLabel() {
        return bridge.selectedDate.length ? Qt.formatDate(localDate(bridge.selectedDate), "MMMM yyyy") : ""
    }
    function dateLabel() {
        return bridge.selectedDate.length ? Qt.formatDate(localDate(bridge.selectedDate), "dddd d MMMM") : ""
    }
    function bandOf(entry) {
        if (!entry || entry.band === undefined || entry.band === null) return -1
        return entry.band
    }
    function roll(strip, event) {
        const pixelsY = event.pixelDelta ? event.pixelDelta.y : 0
        const angleY = event.angleDelta ? event.angleDelta.y : 0
        const pixelsX = event.pixelDelta ? event.pixelDelta.x : 0
        const angleX = event.angleDelta ? event.angleDelta.x : 0
        let delta = pixelsX !== 0 ? pixelsX : angleX
        if (!delta) delta = pixelsY !== 0 ? pixelsY : angleY
        if (!delta) return
        const limit = Math.max(0, strip.contentWidth - strip.width)
        const next = strip.contentX - delta
        if (next < 0) {
            if (strip.contentX <= 0) home.pageWeek(-1)
            else strip.contentX = 0
        } else if (next > limit) {
            if (strip.contentX >= limit - 0.5) home.pageWeek(1)
            else strip.contentX = limit
        } else {
            strip.contentX = next
        }
        event.accepted = true
    }
    function hideMenu() {
        cardMenu.visible = false
        cardMenu.cardItem = null
    }
    function openMenu(entry, card) {
        cardMenu.ruleId = entry.id
        cardMenu.destination = entry.destination || ""
        cardMenu.selection = entry.selection || ""
        cardMenu.band = bandOf(entry)
        cardMenu.kept = !!entry.kept
        cardMenu.dispensed = !!entry.dispensed
        cardMenu.action = entry.action || "Open"
        cardMenu.glossarySlug = entry.glossarySlug || ""
        cardMenu.cardItem = card
        cardMenu.visible = true
        const point = card.mapToItem(home, 0, card.height + 6)
        cardMenu.x = Math.max(8, Math.min(point.x, Math.max(8, home.width - cardMenu.width - 8)))
        cardMenu.y = Math.max(8, Math.min(point.y, Math.max(8, home.height - cardMenu.height - 8)))
    }
    function openFromMenu() {
        const destination = cardMenu.destination
        const selection = cardMenu.selection
        const band = cardMenu.band
        const ruleId = cardMenu.ruleId
        const card = cardMenu.cardItem
        hideMenu()
        if (destination === "fast") {
            if (card) card.flipped = !card.flipped
            return
        }
        cardRequested(destination, selection, band, ruleId)
    }

    readonly property string todayLinkText: bridge.todayLink || ""
    property string watchedDate: bridge.selectedDate || ""
    onWatchedDateChanged: home.hideMenu()

    property bool monthOpen: false
    property bool toldMonth: false
    property bool weekPaging: false
    property bool followCenter: false
    property real panProgress: bridge.review || bridge.reducedMotion === true ? 1 : 0
    property string panKey: (bridge.selectedDate || "") + "|" + (bridge.artworkName || "")
    property string notedKey: ""
    property real panClock: 0

    function tellMonth() {
        if (!bridge.connected || !bridge.setMonthShown) return
        bridge.setMonthShown(home.monthOpen)
    }
    onMonthOpenChanged: home.tellMonth()

    function selectedWeekIndex() {
        const days = bridge.week || []
        for (let index = 0; index < days.length; index++) {
            if (days[index].selected) return index
        }
        const want = bridge.selectedDate || ""
        for (let index = 0; index < days.length; index++) {
            if (days[index].date === want) return index
        }
        return -1
    }
    function centerWeek() {
        const days = bridge.week || []
        if (!days.length || weekStrip.width < 2) return
        let index = Math.floor(days.length / 2)
        if (!home.followCenter) {
            const selected = home.selectedWeekIndex()
            if (selected >= 0) index = selected
        }
        const limit = Math.max(0, weekStrip.contentWidth - weekStrip.width)
        const target = index * 48 - (weekStrip.width - 42) / 2
        weekStrip.contentX = Math.max(0, Math.min(limit, target))
        home.followCenter = false
        home.weekPaging = false
    }
    function pageWeek(direction) {
        if (home.weekPaging || !bridge.shiftWeek) return
        home.weekPaging = true
        home.followCenter = true
        bridge.shiftWeek(direction)
    }
    function nudgeWeek(direction) {
        const step = 48 * 7
        const limit = Math.max(0, weekStrip.contentWidth - weekStrip.width)
        const next = weekStrip.contentX + direction * step
        if (next >= 0 && next <= limit) {
            weekStrip.contentX = next
            return
        }
        home.pageWeek(direction)
    }

    function settlePan() {
        // Review and a screenshot stay on the resting crop and do not write
        // the sidecar. Reduced motion still records the start, as the Mac
        // does, and the picture jumps to that crop.
        if (bridge.review) {
            panAnim.stop()
            panProgress = 1
            return
        }
        const resting = bridge.reducedMotion === true
        if (resting) {
            panAnim.stop()
            panProgress = 1
        }
        const name = bridge.artworkName || ""
        if (!name.length || !bridge.connected || !bridge.noteSayingPan) return
        if (notedKey === panKey && bridge.sayingPanStart > 0) {
            if (!resting) home.applyPanClock()
            return
        }
        notedKey = panKey
        bridge.noteSayingPan(name)
    }
    function applyPanClock() {
        if (bridge.review || bridge.reducedMotion === true) {
            panAnim.stop()
            panProgress = 1
            return
        }
        if (notedKey !== panKey) return
        const start = bridge.sayingPanStart
        if (!(start > 0)) return
        if (panClock === start) return
        const duration = 2 * 36 / 1.15 / 2
        const elapsed = Date.now() / 1000 - start
        const begun = Math.max(0, Math.min(1, elapsed / duration))
        panAnim.stop()
        panClock = start
        panProgress = begun
        if (begun >= 1) return
        panAnim.from = begun
        panAnim.to = 1
        panAnim.duration = (1 - begun) * duration * 1000
        panAnim.start()
    }
    onPanKeyChanged: {
        panClock = 0
        notedKey = ""
        panAnim.stop()
        panProgress = bridge.review || bridge.reducedMotion === true ? 1 : 0
        home.settlePan()
    }

    Connections {
        target: bridge
        function onChanged() {
            if (bridge.connected && !home.toldMonth) {
                home.toldMonth = true
                home.tellMonth()
            }
            home.applyPanClock()
        }
    }
    NumberAnimation {
        id: panAnim
        target: home
        property: "panProgress"
        easing.type: Easing.InOutCubic
    }

    readonly property color ochre: "#a63a38"
    readonly property color fastFill: "#3b3454"
    readonly property color ground: "#15161c"

    readonly property string weekKey: {
        const days = bridge.week || []
        if (!days.length) return ""
        return days[0].date + ":" + days.length + ":" + (bridge.selectedDate || "")
    }
    onWeekKeyChanged: home.centerWeek()

    Column {
        id: mast
        width: parent.width
        spacing: 0

        Item { width: 1; height: 18 }
        Item {
            width: parent.width
            height: 22
            Label {
                anchors.centerIn: parent
                text: home.monthOpen ? (bridge.monthTitle || "") : home.monthLabel()
                color: home.parchment
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Label {
                objectName: "today-link"
                visible: home.todayLinkText.length > 0
                anchors.verticalCenter: parent.verticalCenter
                x: home.todayLinkText.indexOf("Today") === 0 ? parent.width - width - 8 : 8
                text: home.todayLinkText
                color: home.gold
                font.pixelSize: 12
                MouseArea { anchors.fill: parent; onClicked: bridge.selectDate(bridge.today) }
            }
            Label {
                objectName: "month-previous"
                visible: home.monthOpen
                x: Math.max(0, (parent.width - Math.min(600, parent.width - 8)) / 2)
                width: 28
                height: 22
                text: "‹"
                color: home.gold
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                MouseArea { anchors.fill: parent; onClicked: bridge.shiftMonth(-1) }
            }
            Label {
                objectName: "month-next"
                visible: home.monthOpen
                x: Math.min(parent.width - 28, (parent.width + Math.min(600, parent.width - 8)) / 2 - 28)
                width: 28
                height: 22
                text: "›"
                color: home.gold
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                MouseArea { anchors.fill: parent; onClicked: bridge.shiftMonth(1) }
            }
        }
        Item { width: 1; height: 8 }
        Item {
            id: weekFrame
            width: parent.width
            height: home.monthOpen ? 0 : 76
            visible: height > 0.5
            clip: true
            Behavior on height {
                enabled: window.motionOn()
                NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                height: 76
            Label {
                objectName: "week-previous"
                text: "‹"
                width: 18
                height: 54
                verticalAlignment: Text.AlignVCenter
                color: home.gold
                font.pixelSize: 18
                MouseArea { anchors.fill: parent; onClicked: home.nudgeWeek(-1) }
            }
            Item {
                id: weekStrip
                objectName: "week-scroll"
                // Chips are placed by hand. A horizontal ListView on Qt 6.4
                // reported a chip's place and then gave the click to no day.
                width: Math.min(330, Math.max(48, mast.width - 46))
                height: 76
                clip: true
                property real contentX: 0
                property string picked: ""
                readonly property real contentWidth: {
                    const count = bridge.week ? bridge.week.length : 0
                    return count > 0 ? count * 48 - 6 : 0
                }
                onWidthChanged: home.centerWeek()
                Repeater {
                    model: bridge.week
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        objectName: "day-" + modelData.date
                        x: index * 48 - weekStrip.contentX
                        y: 0
                        width: 42
                        height: 54
                        radius: 14
                        color: modelData.fast ? home.fastFill : modelData.selected ? home.ground : Qt.rgba(0.082, 0.086, 0.110, 0.65)
                        border.width: modelData.selected ? 1 : 0
                        border.color: home.gold

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Label {
                                text: ["", "S", "M", "T", "W", "T", "F", "S"][modelData.weekday]
                                color: home.muted
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                width: 30
                            }
                            Label {
                                text: modelData.day
                                color: modelData.feast ? home.gold : (modelData.weekday === 1 ? home.ochre : home.parchment)
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                width: 30
                            }
                            Rectangle {
                                objectName: "settled-" + modelData.date
                                visible: modelData.settled
                                width: 3; height: 3; radius: 2
                                color: home.gold
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
                Item {
                    objectName: (!home.monthOpen && home.selectedWeekIndex() >= 0) ? "calendar-expand" : ""
                    visible: home.selectedWeekIndex() >= 0
                    x: home.selectedWeekIndex() * 48 - weekStrip.contentX - 3
                    y: 56
                    width: 48
                    height: 18
                    z: 3
                    Chevron {
                        anchors.centerIn: parent
                        ink: "#a88a33"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: home.monthOpen = true
                    }
                }
                // The chip under the pointer is chosen from its place in the week.
                MouseArea {
                    anchors.fill: parent
                    anchors.bottomMargin: 18
                    z: 2
                    onPressed: function(mouse) {
                        const index = Math.floor((mouse.x + weekStrip.contentX) / 48)
                        const days = bridge.week || []
                        const day = index >= 0 && index < days.length ? days[index] : null
                        const date = day && day.date ? day.date : ""
                        weekStrip.picked = Math.round(mouse.x) + "=" + date
                        if (date.length) bridge.selectDate(date)
                    }
                }
                WheelHandler {
                    // A laptop touchpad synthesizes the wheel. The default
                    // is a mouse only, so an ordinary Linux wheel would miss.
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    blocking: true
                    onWheel: function(event) { home.roll(weekStrip, event) }
                }
            }
            Label {
                objectName: "week-next"
                text: "›"
                width: 18
                height: 54
                verticalAlignment: Text.AlignVCenter
                color: home.gold
                font.pixelSize: 18
                MouseArea { anchors.fill: parent; onClicked: home.nudgeWeek(1) }
            }
            }
        }
        Item {
            id: monthPane
            objectName: "month-pane"
            visible: home.monthOpen || height > 1
            width: parent.width
            height: home.monthOpen ? 250 : 0
            clip: true
            Behavior on height {
                enabled: window.motionOn()
                NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
            }

            Row {
                y: 4
                width: Math.min(600, parent.width - 24)
                x: (parent.width - width) / 2
                spacing: 0
                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    delegate: Label {
                        required property string modelData
                        width: Math.min(600, monthPane.width - 24) / 7
                        text: modelData
                        color: home.muted
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
            Item {
                id: monthGrid
                objectName: "month-grid"
                y: 22
                width: Math.min(600, parent.width - 24)
                x: (parent.width - width) / 2
                height: 186
                readonly property real cellW: width / 7
                readonly property real cellH: 31
                Repeater {
                    model: bridge.month
                    delegate: Item {
                        required property var modelData
                        required property int index
                        objectName: modelData.inMonth ? ("month-day-" + modelData.date) : ""
                        visible: !!modelData.inMonth
                        x: (index % 7) * monthGrid.cellW
                        y: Math.floor(index / 7) * monthGrid.cellH
                        width: monthGrid.cellW
                        height: 26
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            radius: 8
                            color: modelData.fast ? home.fastFill : modelData.selected ? home.ground : Qt.rgba(0.082, 0.086, 0.110, 0.65)
                            border.width: modelData.selected ? 1 : 0
                            border.color: home.gold
                            Label {
                                anchors.centerIn: parent
                                text: modelData.day
                                color: modelData.feast ? home.gold : (modelData.weekday === 1 ? home.ochre : home.parchment)
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                visible: modelData.settled
                                width: 3
                                height: 3
                                radius: 1.5
                                color: home.gold
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                            }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    z: 2
                    onClicked: function(mouse) {
                        const col = Math.floor(mouse.x / monthGrid.cellW)
                        const row = Math.floor(mouse.y / monthGrid.cellH)
                        if (col < 0 || col > 6 || row < 0 || row > 5) return
                        const days = bridge.month || []
                        const day = days[row * 7 + col]
                        if (day && day.inMonth && day.date) bridge.selectDate(day.date)
                    }
                }
            }
            Item {
                objectName: home.monthOpen ? "calendar-expand" : ""
                x: (parent.width - width) / 2
                y: 214
                width: 48
                height: 18
                Chevron {
                    anchors.centerIn: parent
                    rotation: 180
                    ink: "#a88a33"
                    Behavior on rotation {
                        enabled: window.motionOn()
                        NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: home.monthOpen = false
                }
            }
        }
        Item { width: 1; height: home.monthOpen ? 0 : 4 }
    }
    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: mast.bottom
        anchors.bottom: parent.bottom

    Flickable {
        id: page
        objectName: "home-scroll"
        x: 0
        width: parent.width
        height: parent.height
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: parent.width
            spacing: 0

            Item { width: 1; height: 8 }
            Label {
                width: parent.width
                height: 18
                text: bridge.dayTitle
                color: home.muted
                font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                font.pixelSize: 15
            }
            Item { width: 1; height: 12 }
            Row {
                width: parent.width
                Label {
                    id: dateHeading
                    text: home.dateLabel()
                    color: home.parchment
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Item { width: Math.max(0, content.width - dateHeading.implicitWidth - oldStyleHeading.implicitWidth); height: 1 }
                Label {
                    id: oldStyleHeading
                    visible: bridge.showOldStyleDates && bridge.observedDate.length > 0
                             && bridge.observedDate !== bridge.selectedDate
                    text: visible ? Qt.formatDate(home.localDate(bridge.observedDate), "d MMM") + " o.s." : ""
                    color: home.muted
                    font.pixelSize: 12
                }
            }
            Item { width: 1; height: 17 }
            Row {
                spacing: 8
                Label { text: "Today's Commitments"; color: home.muted; font.pixelSize: 12 }
                Label {
                    objectName: "home-add-rule"
                    text: "Add a New Rule"
                    color: home.gold
                    font.pixelSize: 12
                    MouseArea { anchors.fill: parent; onClicked: home.libraryRequested() }
                }
            }
            Item { width: 1; height: 17 }

            ListView {
                id: cardStrip
                objectName: "card-scroll"
                // The row that used to live here left delegate parents unusable,
                // so a click could not be mapped back to the card.
                width: parent.width
                height: 236
                property int expandedCards: 0
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 4000
                model: bridge.entries
                delegate: Rectangle {
                            id: card
                            required property var modelData
                            objectName: "card-" + modelData.id
                            property bool expanded: false
                            property bool flipped: false
                            width: 132
                            height: 232
                            radius: 22
                            color: "#e8dfcd"
                            Behavior on width {
                                enabled: window.motionOn()
                                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                            }
                            Behavior on height {
                                enabled: window.motionOn()
                                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        home.openMenu(modelData, card)
                                        return
                                    }
                                    // Expanding is its own control. A click on an
                                    // expanded card only puts it back.
                                    if (card.expanded) {
                                        card.expanded = false
                                        card.width = 132
                                        card.height = 232
                                        cardStrip.expandedCards = Math.max(0, cardStrip.expandedCards - 1)
                                        if (cardStrip.expandedCards === 0)
                                            cardStrip.height = 236
                                        return
                                    }
                                    if (modelData.destination === "fast") {
                                        card.flipped = !card.flipped
                                        return
                                    }
                                    home.cardRequested(
                                        modelData.destination || "",
                                        modelData.selection || "",
                                        home.bandOf(modelData),
                                        modelData.id)
                                }
                            }
                            Icon {
                                x: 14; y: 14
                                kind: modelData.category
                                tint: home.gold
                                width: 17; height: 17
                            }
                            Label {
                                x: 14; y: 42
                                text: modelData.category
                                color: "#726e5f"
                                font.pixelSize: 11
                            }
                            Rectangle {
                                objectName: "completion-" + modelData.id
                                z: 2
                                x: parent.width - 31; y: 10
                                width: 21; height: 21; radius: 11
                                color: modelData.kept || modelData.dispensed ? home.gold : "transparent"
                                border.color: "#b89842"
                                border.width: 1
                                Label {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    visible: modelData.kept || modelData.dispensed
                                    color: home.ink
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !modelData.dispensed
                                    onClicked: bridge.toggleKept(modelData.id)
                                }
                            }
                            Label {
                                id: titleLabel
                                objectName: "card-title-" + modelData.id
                                x: 14
                                y: 62
                                width: parent.width - 28
                                height: card.expanded ? implicitHeight : 56
                                text: modelData.title
                                wrapMode: Text.WordWrap
                                maximumLineCount: card.expanded ? 8 : 4
                                fontSizeMode: card.expanded ? Text.FixedSize : Text.Fit
                                minimumPixelSize: 11
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignTop
                                color: home.ink
                                font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                                font.pixelSize: 18
                            }
                            Label {
                                id: summaryLabel
                                objectName: "card-summary-" + modelData.id
                                x: 14; y: 120
                                width: parent.width - 28
                                height: card.expanded ? implicitHeight : 72
                                text: card.flipped ? (modelData.back || modelData.summary) : modelData.summary
                                wrapMode: Text.Wrap
                                maximumLineCount: card.expanded ? 24 : (card.flipped ? 5 : 4)
                                elide: card.expanded ? Text.ElideNone : Text.ElideRight
                                color: "#5f5b50"
                                font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                                font.pixelSize: 13
                            }
                            Label {
                                x: 14
                                y: card.expanded ? parent.height - 24 : 207
                                visible: !card.flipped
                                text: modelData.dispensed ? "Lifted Today"
                                     : modelData.stoodDown ? "Stood Down"
                                     : modelData.time
                                color: "#5f5b50"
                                font.pixelSize: 11
                            }
                            Label {
                                objectName: "card-learn-" + modelData.id
                                z: 4
                                visible: card.flipped && (modelData.glossarySlug || "").length > 0
                                x: 14
                                y: parent.height - 28
                                text: "Learn More"
                                color: "#8a6d1f"
                                font.pixelSize: 11
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: window.openGlossary(modelData.glossarySlug)
                                }
                            }
                            Label {
                                objectName: "expand-" + modelData.id
                                z: 3
                                visible: summaryLabel.truncated && !card.expanded && !card.flipped
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                text: "Expand"
                                color: "#8a6d1f"
                                font.pixelSize: 11
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: {
                                        card.expanded = true
                                        card.width = 280
                                        const grown = Math.max(280, summaryLabel.y + summaryLabel.implicitHeight + 46)
                                        card.height = grown
                                        cardStrip.expandedCards += 1
                                        cardStrip.height = Math.max(cardStrip.height, grown)
                                    }
                                }
                            }
                        }
                footer: Rectangle {
                    objectName: "home-add-placard"
                    width: 120
                    height: 232
                    radius: 21
                    color: "transparent"
                    border.color: "#7d671f"
                    border.width: 1
                    Label {
                        anchors.centerIn: parent
                        text: "+  Add"
                        color: home.gold
                        font.pixelSize: 14
                    }
                    MouseArea { anchors.fill: parent; onClicked: home.libraryRequested() }
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    blocking: true
                    onWheel: function(event) { home.roll(cardStrip, event) }
                }
            }
            Item { width: 1; height: 17 }
            Rectangle {
                id: sayingCard
                width: parent.width
                height: 270
                radius: 20
                color: "#27252a"
                clip: true
                ArtworkImage {
                    objectName: "saying-art"
                    anchors.fill: parent
                    source: bridge.artworkUrl
                    drifting: true
                    progress: home.panProgress
                }
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 18
                    spacing: 5
                    Label { text: "Sayings of the Church Fathers"; color: home.parchment; font.pixelSize: 11 }
                    Label {
                        id: sayingQuote
                        width: parent.width
                        text: bridge.sayingText
                        wrapMode: Text.Wrap
                        color: home.parchment
                        font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                        font.pixelSize: 18
                    }
                    Label {
                        id: sayingCredit
                        width: parent.width
                        text: bridge.sayingAuthor + " · " + bridge.sayingSource
                        wrapMode: Text.Wrap
                        color: home.parchment
                        font.pixelSize: 12
                    }
                }
            }
            Item { width: 1; height: 24 }
        }
        EdgeFade {
            y: page.contentY
            width: page.width
            height: page.height
            z: 4
        }
    }
    }

    MouseArea {
        anchors.fill: parent
        z: 20
        visible: cardMenu.visible
        enabled: cardMenu.visible
        onClicked: home.hideMenu()
    }

    Rectangle {
        id: cardMenu
        objectName: "card-menu"
        visible: false
        z: 30
        // A Label's implicitHeight ignores an explicit height, so the old
        // menuColumn.implicitHeight binding collapsed this rectangle to one
        // row and clicks below it hit the dismiss layer.
        // Lifted or the day actions, then About This Rule when the rule has a
        // term, then Edit. Pause is not on this menu.
        readonly property int menuRows: (dispensed ? 1 : (kept ? 3 : 4))
                + (glossarySlug.length > 0 ? 1 : 0) + 1
        width: 248
        height: menuRows * 32 + 12
        radius: 10
        color: "#1c1e26"
        border.color: "#343237"
        property string ruleId: ""
        property string destination: ""
        property string selection: ""
        property int band: -1
        property bool kept: false
        property bool dispensed: false
        property string action: ""
        property string glossarySlug: ""
        property var cardItem: null

        MouseArea { anchors.fill: parent }

        // Rows are placed by hand. A Column reports the right offsets and
        // then delivers every click to the last row.
        Item {
            id: menuColumn
            z: 1
            x: 6
            y: 6
            width: parent.width - 12
            height: cardMenu.menuRows * 32

            Item {
                id: liftedRow
                objectName: "card-menu-lifted"
                visible: cardMenu.dispensed
                y: 0
                width: parent.width
                height: visible ? 32 : 0
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: "Lifted by the Church Today"
                    color: home.muted
                    font.pixelSize: 13
                }
            }
            Item {
                id: actionRow
                objectName: "card-menu-action"
                visible: !cardMenu.dispensed
                y: liftedRow.y + liftedRow.height
                width: parent.width
                height: visible ? 32 : 0
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: cardMenu.action
                    color: home.parchment
                    font.pixelSize: 13
                }
                MouseArea { anchors.fill: parent; onClicked: home.openFromMenu() }
            }
            Item {
                id: keptRow
                objectName: "card-menu-kept"
                visible: !cardMenu.dispensed
                y: actionRow.y + actionRow.height
                width: parent.width
                height: visible ? 32 : 0
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: cardMenu.kept ? "Clear This Day" : "Mark as Kept"
                    color: home.parchment
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) {
                        const id = cardMenu.ruleId
                        home.hideMenu()
                        bridge.toggleKept(id)
                    }
                }
            }
            Item {
                id: lateRow
                objectName: "card-menu-late"
                visible: !cardMenu.dispensed && !cardMenu.kept
                y: keptRow.y + keptRow.height
                width: parent.width
                height: visible ? 32 : 0
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: "Mark as Kept, Late"
                    color: home.parchment
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const id = cardMenu.ruleId
                        home.hideMenu()
                        bridge.markKeptLate(id)
                    }
                }
            }
            Item {
                id: standRow
                objectName: "card-menu-stand"
                visible: !cardMenu.dispensed
                y: lateRow.y + lateRow.height
                width: parent.width
                height: visible ? 32 : 0
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: "Stand Down for This Day"
                    color: home.parchment
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) {
                        const id = cardMenu.ruleId
                        home.hideMenu()
                        bridge.standDownDay(id)
                    }
                }
            }
            Item {
                id: aboutRow
                objectName: "card-menu-about"
                visible: cardMenu.glossarySlug.length > 0
                y: standRow.y + standRow.height
                width: parent.width
                height: visible ? 32 : 0
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: "About This Rule"
                    color: home.parchment
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const slug = cardMenu.glossarySlug
                        home.hideMenu()
                        window.openGlossary(slug)
                    }
                }
            }
            Item {
                id: editRow
                objectName: "card-menu-edit"
                y: aboutRow.y + aboutRow.height
                width: parent.width
                height: 32
                Label {
                    anchors.fill: parent
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: "Edit Rule…"
                    color: home.parchment
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const id = cardMenu.ruleId
                        home.hideMenu()
                        home.cardRequested("editor", "", -1, id)
                    }
                }
            }
        }
    }

}
