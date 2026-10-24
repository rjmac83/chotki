import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: prayers
    objectName: "prayers"
    width: parent ? parent.width : 800
    height: parent ? parent.height : 700

    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color ink: "#1a1916"
    readonly property color panel: "#1c1e26"
    readonly property color line: "#23252c"

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }

    function syncChooser() {
        const wanted = bridge.prayerRopeAlone ? "" : bridge.prayerSelection
        for (let index = 0; index < bridge.prayerChoices.length; index++) {
            if (bridge.prayerChoices[index].id === wanted) {
                if (chooser.currentIndex !== index) chooser.currentIndex = index
                return
            }
        }
    }

    Shortcut {
        sequence: "Space"
        enabled: bridge.showsRope
        onActivated: bridge.advancePrayer()
    }

    Connections {
        target: bridge
        function onChanged() { prayers.syncChooser() }
    }

    Component.onCompleted: {
        if (window.openPsalter) prayers.psalterOpen = true
        bridge.refreshPrayer()
        syncChooser()
    }

    property bool psalterOpen: false

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: prayers.psalterOpen
            active: prayers.psalterOpen
            visible: prayers.psalterOpen
            source: "Psalter.qml"
            onLoaded: item.closeRequested.connect(function() { prayers.psalterOpen = false })
        }

        ComboBox {
            visible: !prayers.psalterOpen
            id: chooser
            objectName: "prayer-chooser"
            model: bridge.prayerChoices
            textRole: "title"
            font.pixelSize: 15
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 280
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            onActivated: function(index) {
                const choice = bridge.prayerChoices[index]
                if (choice) bridge.choosePrayer(choice.id)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: bridge.showsRope && !prayers.psalterOpen
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 248

                Item {
                    id: rope
                    width: 240
                    height: 240
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top

                    Canvas {
                        id: ring
                        anchors.fill: parent
                        antialiasing: true
                        onPaint: {
                            const context = getContext("2d")
                            context.reset()
                            const knots = bridge.prayerKnots
                            if (!knots || knots.length === 0) return
                            const layoutSide = bridge.prayerDiameter > 0 ? bridge.prayerDiameter : width
                            const scale = width / layoutSide
                            const dot = bridge.prayerDot * scale
                            const bead = bridge.prayerBead * scale
                            // Same circle as the Mac rope. ellipse() here is a
                            // bounding box, so the old call drew half a knot.
                            function disc(centre, diameter, fill, stroke, width) {
                                context.beginPath()
                                context.arc(centre.x * scale, centre.y * scale,
                                            diameter / 2, 0, Math.PI * 2)
                                if (fill) {
                                    context.fillStyle = fill
                                    context.fill()
                                }
                                if (stroke) {
                                    context.strokeStyle = stroke
                                    context.lineWidth = width
                                    context.stroke()
                                }
                            }
                            for (let index = 0; index < knots.length; index++) {
                                const knot = knots[index]
                                if (knot.mark === "counted") disc(knot, dot, prayers.gold, "", 0)
                                else if (knot.mark === "next") disc(knot, dot, prayers.panel, prayers.gold, Math.max(1.2, dot * 0.28))
                                else disc(knot, dot, prayers.panel, "rgba(130, 125, 112, 0.55)", Math.max(0.7, dot * 0.14))
                            }
                            const beads = bridge.prayerBeads
                            for (let index = 0; index < beads.length; index++) {
                                const beadPoint = beads[index]
                                disc(beadPoint, bead, beadPoint.passed ? "#a63a38" : "rgba(166, 58, 56, 0.55)", "", 0)
                            }
                        }
                        Connections {
                            target: bridge
                            function onChanged() { ring.requestPaint() }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Label {
                            objectName: "prayer-count-value"
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: bridge.prayerCount
                            color: prayers.gold
                            font.pixelSize: 64
                            font.weight: Font.Light
                        }
                        Label {
                            objectName: "prayer-status"
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: bridge.prayerComplete ? "the knot is complete" : "of " + bridge.prayerTarget
                            color: bridge.prayerComplete ? prayers.gold : prayers.muted
                            font.pixelSize: 13
                        }
                    }

                    MouseArea {
                        objectName: "prayer-rope"
                        anchors.fill: parent
                        Accessible.name: "Prayer rope, " + bridge.prayerCount + " of " + bridge.prayerTarget + " knots counted"
                        onClicked: bridge.advancePrayer()
                    }
                }

                Label {
                    objectName: "prayer-start-again"
                    text: "Start again"
                    color: prayers.muted
                    font.pixelSize: 13
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 22
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: bridge.startAgain()
                    }
                }
            }

            Rectangle {
                objectName: "prayer-count"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 320
                Layout.preferredHeight: 40
                radius: 6
                color: prayers.gold
                Label {
                    anchors.centerIn: parent
                    text: "Count"
                    color: prayers.ink
                    font.pixelSize: 15
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: bridge.advancePrayer()
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 7
                Layout.bottomMargin: 12
                text: "Click, or press space."
                color: prayers.faint
                font.pixelSize: 15
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !bridge.prayerRopeAlone && !prayers.psalterOpen
            Flickable {
            id: prayerScroll
            anchors.fill: parent
            contentHeight: words.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // The wheel moves a long rule. A click still reaches a term link.
            interactive: true

            Column {
                id: words
                width: parent.width
                spacing: 16
                topPadding: 16
                bottomPadding: 24

                Repeater {
                    model: bridge.prayerWords
                    delegate: Column {
                        required property var modelData
                        width: words.width
                        spacing: 6

                        Label {
                            width: parent.width
                            text: modelData.title
                            color: prayers.gold
                            font.pixelSize: 15
                            wrapMode: Text.WordWrap
                            horizontalAlignment: modelData.centred ? Text.AlignHCenter : Text.AlignLeft
                        }
                        Label {
                            width: parent.width
                            visible: modelData.rubric !== undefined && String(modelData.rubric).length > 0
                            text: modelData.rubric || ""
                            color: prayers.faint
                            font.pixelSize: 12
                            font.italic: true
                            wrapMode: Text.WordWrap
                            horizontalAlignment: modelData.centred ? Text.AlignHCenter : Text.AlignLeft
                        }
                        Repeater {
                            model: modelData.paragraphs
                            delegate: Text {
                                required property int index
                                required property string modelData
                                objectName: "prayer-line"
                                property string plain: modelData
                                width: words.width
                                text: {
                                    const block = parent.modelData
                                    const lines = block ? block.html : null
                                    if (lines && index < lines.length && lines[index]) return lines[index]
                                    return plain
                                }
                                textFormat: Text.RichText
                                color: prayers.parchment
                                font.family: charter.status === FontLoader.Ready ? charter.name : "serif"
                                font.pixelSize: 20
                                wrapMode: Text.WordWrap
                                horizontalAlignment: parent.modelData && parent.modelData.centred
                                                   ? Text.AlignHCenter : Text.AlignLeft
                                onLinkActivated: function(link) {
                                    if (link) window.openGlossary(link)
                                }
                            }
                        }
                        Label {
                            width: parent.width
                            text: "Source · " + (modelData.source || "")
                            color: prayers.faint
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            horizontalAlignment: modelData.centred ? Text.AlignHCenter : Text.AlignLeft
                        }
                    }
                }
            }
            EdgeFade {
                y: prayerScroll.contentY
                width: prayerScroll.width
                height: prayerScroll.height
                z: 8
            }
            }
        }

        Rectangle {
            visible: !prayers.psalterOpen
            Layout.fillWidth: true
            height: 1
            color: prayers.line
        }

        RowLayout {
            visible: !prayers.psalterOpen
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            spacing: 8

            Repeater {
                model: bridge.showsRope ? bridge.prayerTargets : []
                delegate: Rectangle {
                    required property var modelData
                    objectName: "prayer-target-" + modelData
                    width: 42
                    height: 26
                    radius: 4
                    color: bridge.prayerTarget === modelData ? prayers.gold : prayers.panel
                    Label {
                        anchors.centerIn: parent
                        text: modelData
                        color: bridge.prayerTarget === modelData ? prayers.ink : prayers.muted
                        font.pixelSize: 15
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bridge.aimPrayer(modelData)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                objectName: "prayer-psalter"
                text: "The Psalter"
                color: prayers.gold
                font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: prayers.psalterOpen = true
                }
            }

            Label {
                objectName: "prayer-rope-toggle"
                text: bridge.showsRope ? "Hide rope" : "Show rope"
                color: prayers.gold
                font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: bridge.showRope(!bridge.showsRope)
                }
            }
        }
    }
}
