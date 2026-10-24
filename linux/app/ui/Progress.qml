import QtQuick
import QtQuick.Controls
import ChotkiArtwork 1.0

Item {
    id: progress
    objectName: "progress"
    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }
    function face() { return charter.status === FontLoader.Ready ? charter.name : "serif" }

    function roll(event) {
        const pixels = event.pixelDelta ? event.pixelDelta.y : 0
        const angle = event.angleDelta ? event.angleDelta.y : 0
        const delta = pixels !== 0 ? pixels : angle
        if (!delta) return
        const limit = Math.max(0, reportScroll.contentHeight - reportScroll.height)
        reportScroll.contentY = Math.max(0, Math.min(limit, reportScroll.contentY - delta))
        event.accepted = true
    }

    property bool confirmingReset: false

    Component.onCompleted: bridge.showProgress()

    Flickable {
        id: reportScroll
        objectName: "progress-scroll"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: art.top
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: parent.width
            spacing: 0

            Label {
                objectName: "progress-heading"
                x: 24
                width: parent.width - 48
                text: bridge.progressHeading
                color: progress.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                topPadding: 8
                bottomPadding: 4
            }

            Label {
                objectName: "progress-reset"
                x: 24
                text: "Reset record"
                color: progress.muted
                font.pixelSize: 14
                topPadding: 4
                bottomPadding: 4
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: progress.confirmingReset = true
                }
            }

            Label {
                objectName: "progress-notice"
                x: 24
                width: column.width - 48
                visible: (bridge.progressNotice || "").length > 0
                text: bridge.progressNotice || ""
                wrapMode: Text.WordWrap
                color: progress.parchment
                font.pixelSize: 14
                topPadding: 2
                bottomPadding: 6
            }

            Repeater {
                model: bridge.progressSummary
                delegate: Label {
                    required property var modelData
                    objectName: "progress-summary"
                    x: 24
                    width: column.width - 48
                    text: modelData
                    color: progress.parchment
                    font.family: progress.face()
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                    topPadding: 3
                    bottomPadding: 3
                }
            }

            Item {
                x: 24
                width: column.width - 48
                height: bridge.progressFigure.length > 0 ? 48 : 0
                visible: height > 0
                Label {
                    id: figureLabel
                    objectName: "progress-figure"
                    y: 14
                    text: bridge.progressFigure + "%"
                    color: progress.gold
                    font.pixelSize: 26
                }
                Label {
                    objectName: "progress-figure-note"
                    anchors.left: figureLabel.right
                    anchors.leftMargin: 8
                    anchors.baseline: figureLabel.baseline
                    text: bridge.progressFigureNote
                    color: progress.muted
                    font.pixelSize: 14
                }
            }

            Rectangle {
                x: 24
                width: column.width - 48
                height: bridge.progressRules.length > 0 ? 1 : 0
                color: progress.line
                visible: height > 0
            }

            Label {
                x: 24
                visible: bridge.progressRules.length > 0
                text: "By Rule"
                color: progress.muted
                font.pixelSize: 13
                topPadding: 10
                bottomPadding: 5
            }

            Repeater {
                model: bridge.progressRules
                delegate: Item {
                    required property var modelData
                    x: 24
                    width: column.width - 48
                    height: 28
                    Label {
                        anchors.left: parent.left
                        anchors.right: countLabel.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        color: progress.parchment
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                    Label {
                        id: countLabel
                        objectName: "progress-count"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.count
                        color: progress.muted
                        font.pixelSize: 13
                    }
                }
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            blocking: true
            onWheel: function(event) { progress.roll(event) }
        }

        EdgeFade {
            y: reportScroll.contentY
            width: reportScroll.width
            height: reportScroll.height
            z: 8
        }
    }

    Rectangle {
        objectName: "progress-reset-confirm"
        visible: progress.confirmingReset
        anchors.fill: parent
        z: 20
        color: "#cc101218"
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent
            width: Math.min(420, parent.width - 48)
            spacing: 12
            Label {
                objectName: "progress-reset-title"
                width: parent.width
                text: "Are you sure?"
                color: progress.parchment
                font.pixelSize: 18
                wrapMode: Text.WordWrap
            }
            Label {
                objectName: "progress-reset-message"
                width: parent.width
                text: "This will completely erase your record and cannot be undone."
                color: progress.parchment
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            Row {
                spacing: 18
                Label {
                    objectName: "progress-reset-yes"
                    text: "Yes"
                    color: progress.gold
                    font.pixelSize: 15
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: {
                            progress.confirmingReset = false
                            bridge.resetRecord()
                        }
                    }
                }
                Label {
                    objectName: "progress-reset-cancel"
                    text: "Cancel"
                    color: progress.muted
                    font.pixelSize: 15
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: progress.confirmingReset = false
                    }
                }
            }
        }
    }

    // The day's saying pans. This pane does not.
    Item {
        id: art
        objectName: "progress-art"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // The Mac strip is 300 tall and pins the top of the icon. A wider
        // window cover-scales, and a strip that stayed 300 would push the
        // faces out the bottom. Grow so the halo band stays inside, and
        // never taller than the page, so a short window cannot clip the heads.
        height: {
            const page = parent ? parent.height : 0
            let strip = 300
            const iw = fresco.imageWidth
            const ih = fresco.imageHeight
            if (iw > 0 && ih > 0 && width > 0) {
                const needed = ih * fresco.progressFaceBand * width / iw
                if (needed > strip) strip = needed
            }
            if (page > 0 && strip > page) strip = page
            return strip
        }

        Rectangle { anchors.fill: parent; color: "#27252a" }

        ArtworkImage {
            id: fresco
            objectName: "progress-image"
            anchors.fill: parent
            source: bridge.progressArtworkUrl
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            anchors.bottomMargin: 16
            spacing: 6

            Label {
                objectName: "progress-quote"
                width: parent.width
                text: "“Those who have really determined to serve Christ, with the help of spiritual fathers and their own self-knowledge, will strive before all else to choose a place, a way of life, a habitation, and exercises suitable for them.”"
                color: progress.parchment
                font.family: progress.face()
                font.pixelSize: 16
                font.italic: true
                wrapMode: Text.WordWrap
            }
            Label {
                objectName: "progress-credit"
                width: parent.width
                text: "— Saint John Climacus · The Ladder of Divine Ascent"
                color: progress.parchment
                font.pixelSize: 12
                leftPadding: 28
                wrapMode: Text.WordWrap
            }
            Label {
                objectName: "progress-caption"
                width: parent.width
                text: "Icon of St. Anthony the Great, St. Paul of Thebes, St. Sabbas the Sanctified, and St. John Climacus."
                color: progress.parchment
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
