import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: reading
    objectName: "reading"
    readonly property color parchment: "#e8dfcd"
    readonly property color parchmentDim: "#d8cfbd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"
    readonly property color line: "#23252c"

    FontLoader { id: charter; source: "fonts/XCharter-Roman.otf" }

    function face() { return charter.status === FontLoader.Ready ? charter.name : "serif" }

    function htmlEscape(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function spanHtml(spans) {
        let html = ""
        const list = spans || []
        for (let index = 0; index < list.length; index++) {
            let piece = reading.htmlEscape(list[index].text || "")
            if (list[index].bold) piece = "<b>" + piece + "</b>"
            if (list[index].italic) piece = "<i>" + piece + "</i>"
            html += piece
        }
        return html
    }

    Flickable {
        id: reader
        objectName: "reading-scroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        property var finishedBands: []

        function noteScroll(delta) {
            userMoved = true
            contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + delta))
            Qt.callLater(considerEnds)
        }
        property bool userMoved: false

        function considerEnds() {
            if (!userMoved) return
            const marks = []
            function walk(item) {
                if (!item) return
                const name = item.objectName || ""
                if (String(name).indexOf("reading-end-") === 0) marks.push(item)
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
                const band = mark.band
                if (finishedBands.indexOf(band) >= 0) continue
                finishedBands = finishedBands.concat([band])
                bridge.finishReading(band)
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

        Shortcut { sequence: "Down"; onActivated: reader.noteScroll(48) }
        Shortcut { sequence: "Up"; onActivated: reader.noteScroll(-48) }
        Shortcut { sequence: "PgDown"; onActivated: reader.noteScroll(reader.height * 0.85) }
        Shortcut { sequence: "PgUp"; onActivated: reader.noteScroll(-reader.height * 0.85) }
        Shortcut { sequence: "End"; onActivated: reader.noteScroll(reader.contentHeight) }

        Column {
            id: column
            width: reader.width
            spacing: 0

            Column {
                width: parent.width
                spacing: 8
                topPadding: 16
                leftPadding: 24
                rightPadding: 24
                visible: bridge.readingWaiting.length > 0
                Label {
                    width: parent.width - 48
                    text: bridge.readingWaiting
                    color: reading.muted
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Label {
                    width: parent.width - 48
                    text: bridge.readingWaitingDetail
                    color: reading.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }

            Column {
                width: parent.width
                spacing: 0
                visible: bridge.readingWaiting.length === 0
                leftPadding: 24
                rightPadding: 24
                topPadding: 16
                bottomPadding: 24

                Label {
                    objectName: "reading-day-title"
                    width: parent.width - 48
                    visible: text.length > 0
                    text: bridge.readingTitle
                    color: reading.muted
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Text {
                    objectName: "reading-summary"
                    property string plain: bridge.readingSummary
                    width: parent.width - 48
                    text: bridge.readingSummaryHtml || bridge.readingSummary
                    textFormat: Text.RichText
                    color: reading.gold
                    font.family: reading.face()
                    font.pixelSize: 22
                    wrapMode: Text.WordWrap
                    topPadding: 6
                    bottomPadding: 10
                    onLinkActivated: function(link) {
                        if (link) window.openGlossary(link)
                    }
                }
                Text {
                    objectName: "reading-fast-note"
                    property string plain: bridge.readingFastNote
                    width: parent.width - 48
                    visible: plain.length > 0
                    text: bridge.readingFastNoteHtml || bridge.readingFastNote
                    textFormat: Text.RichText
                    color: "#9a8fc4"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    onLinkActivated: function(link) {
                        if (link) window.openGlossary(link)
                    }
                }
                Label {
                    width: parent.width - 48
                    visible: text.length > 0
                    text: bridge.readingAbstentionNote
                    color: reading.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    bottomPadding: 10
                }

                Repeater {
                    model: bridge.readingSections
                    delegate: Column {
                        id: section
                        required property var modelData
                        width: column.width - 48
                        spacing: 12
                        topPadding: 8
                        bottomPadding: 8
                        property int band: modelData.band

                        Rectangle { width: parent.width; height: 1; color: reading.line }
                        Item {
                            width: parent.width
                            height: heading.implicitHeight
                            Row {
                                id: heading
                                width: parent.width
                                spacing: 10
                                Label {
                                    width: parent.width - 28
                                    text: section.modelData.title
                                    color: reading.parchment
                                    font.family: reading.face()
                                    font.pixelSize: 22
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    text: section.modelData.open ? "⌃" : "⌄"
                                    color: reading.gold
                                    font.pixelSize: 14
                                }
                            }
                            MouseArea {
                                objectName: "reading-section-" + section.band
                                anchors.fill: parent
                                onClicked: bridge.toggleReading(section.band)
                            }
                        }

                        Column {
                            objectName: "reading-body-" + section.band
                            width: parent.width
                            spacing: 16
                            visible: section.modelData.open

                            Repeater {
                                model: section.modelData.passages || []
                                delegate: Column {
                                    required property var modelData
                                    width: section.width
                                    spacing: 8
                                    Label {
                                        objectName: "reading-citation-" + section.band
                                        width: parent.width
                                        text: modelData.citation
                                        color: reading.muted
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                    }
                                    Label {
                                        objectName: "reading-passage-" + section.band
                                        width: parent.width
                                        text: modelData.text
                                        color: reading.parchmentDim
                                        font.family: reading.face()
                                        font.pixelSize: 18
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.25
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 10
                                visible: section.modelData.life !== undefined && section.modelData.life
                                Label {
                                    width: parent.width
                                    visible: section.modelData.life && section.modelData.life.dates
                                    text: section.modelData.life ? section.modelData.life.dates : ""
                                    color: reading.gold
                                    font.family: reading.face()
                                    font.pixelSize: 19
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    width: parent.width
                                    visible: section.modelData.life && section.modelData.life.preface
                                    text: section.modelData.life ? section.modelData.life.preface : ""
                                    color: reading.parchment
                                    font.family: reading.face()
                                    font.pixelSize: 18
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    objectName: "reading-life-unavailable"
                                    width: parent.width
                                    visible: section.modelData.life && !section.modelData.life.available
                                    text: section.modelData.life
                                          ? (section.modelData.life.saints ? section.modelData.life.saints + "\n" : "")
                                            + section.modelData.life.unavailable
                                          : ""
                                    color: reading.faint
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Repeater {
                                    model: section.modelData.life && section.modelData.life.available
                                           ? section.modelData.life.sections : []
                                    delegate: Column {
                                        required property var modelData
                                        width: section.width
                                        spacing: 8
                                        Label {
                                            width: parent.width
                                            text: modelData.heading
                                            color: reading.parchment
                                            font.family: reading.face()
                                            font.pixelSize: 18
                                            wrapMode: Text.WordWrap
                                        }
                                        Repeater {
                                            model: modelData.blocks || []
                                            delegate: Column {
                                                required property var modelData
                                                width: section.width
                                                spacing: 4
                                                Label {
                                                    width: parent.width
                                                    visible: modelData.kind === "heading"
                                                    text: modelData.text || ""
                                                    color: reading.parchmentDim
                                                    font.family: reading.face()
                                                    font.pixelSize: 17
                                                    wrapMode: Text.WordWrap
                                                }
                                                Label {
                                                    width: parent.width
                                                    visible: modelData.kind !== "heading" && modelData.kind !== "lines"
                                                    text: reading.spanHtml(modelData.spans)
                                                    textFormat: Text.RichText
                                                    color: reading.parchmentDim
                                                    font.family: reading.face()
                                                    font.pixelSize: 18
                                                    wrapMode: Text.WordWrap
                                                    lineHeight: 1.25
                                                }
                                                Repeater {
                                                    model: modelData.kind === "lines" ? modelData.rows : []
                                                    delegate: Label {
                                                        required property var modelData
                                                        width: section.width
                                                        text: reading.spanHtml(modelData)
                                                        textFormat: Text.RichText
                                                        color: reading.parchmentDim
                                                        font.family: reading.face()
                                                        font.pixelSize: 18
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Column {
                                    width: parent.width
                                    spacing: 4
                                    visible: section.modelData.life && section.modelData.life.available
                                    Label {
                                        width: parent.width
                                        text: section.modelData.life ? section.modelData.life.source : ""
                                        color: reading.faint
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                    Label {
                                        objectName: "reading-life-license"
                                        width: parent.width
                                        text: section.modelData.life ? section.modelData.life.licenseNote : ""
                                        color: reading.faint
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                    Label {
                                        width: parent.width
                                        text: section.modelData.life ? section.modelData.life.license : ""
                                        color: reading.faint
                                        font.pixelSize: 12
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 10
                                visible: section.modelData.appointed !== undefined && section.modelData.appointed
                                Label {
                                    width: parent.width
                                    text: section.modelData.appointed ? section.modelData.appointed.heading : ""
                                    color: reading.muted
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    width: parent.width
                                    visible: section.modelData.appointed && section.modelData.appointed.note
                                    text: section.modelData.appointed ? section.modelData.appointed.note : ""
                                    color: reading.muted
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Repeater {
                                    model: section.modelData.appointed ? section.modelData.appointed.paragraphs : []
                                    delegate: Label {
                                        required property var modelData
                                        width: section.width
                                        text: modelData
                                        color: reading.parchmentDim
                                        font.family: reading.face()
                                        font.pixelSize: 18
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.25
                                    }
                                }
                                Label {
                                    width: parent.width
                                    text: section.modelData.appointed ? section.modelData.appointed.source : ""
                                    color: reading.faint
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Item {
                                objectName: "reading-end-" + section.band
                                property int band: section.band
                                width: parent.width
                                height: 1
                                visible: section.modelData.open
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width - 48
                    height: 1
                    color: reading.line
                    visible: bridge.readingFathers.length > 0
                }
                Label {
                    width: parent.width - 48
                    visible: bridge.readingFathers.length > 0
                    text: "From the Fathers"
                    color: reading.muted
                    font.pixelSize: 13
                    topPadding: 10
                }
                Label {
                    width: parent.width - 48
                    visible: bridge.readingFathers.length > 0
                    text: bridge.readingFathers
                    color: reading.parchmentDim
                    font.family: reading.face()
                    font.pixelSize: 18
                    wrapMode: Text.WordWrap
                }
                Label {
                    width: parent.width - 48
                    visible: bridge.readingFathersBy.length > 0
                    text: bridge.readingFathersBy
                    color: reading.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    bottomPadding: 10
                }
                Rectangle { width: parent.width - 48; height: 1; color: reading.line }
                Label {
                    objectName: "reading-footer"
                    width: parent.width - 48
                    text: bridge.readingFooter
                    color: reading.faint
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    topPadding: 8
                }
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
