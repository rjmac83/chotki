import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: form
    objectName: "editor"
    readonly property color parchment: "#e8dfcd"
    readonly property color muted: "#a39e8f"
    readonly property color faint: "#827d70"
    readonly property color gold: "#c9a227"

    property int loadedToken: -1
    property bool isNew: true
    property bool paused: false
    property string ruleId: ""
    property string titleDraft: ""
    property string noteDraft: ""
    property string sourceDraft: ""
    property string kind: "Every day"
    property var kinds: []
    property var days: []
    property int monthDay: 1
    property string shortMonth: "lastDay"
    property string season: "greatLent"
    property var seasons: []
    property string onceDate: ""
    property bool hasTime: false
    property int hour: 6
    property int minute: 30
    property bool reminders: true
    property var leadChoices: []
    property string fatherName: ""
    property bool givenByPriest: false
    property string scope: "wholeSeries"
    property var scopes: []

    function load() {
        const page = bridge.editorPage
        if (!page || page.open !== true) return
        loadedToken = page.token
        isNew = page.isNew === true
        paused = page.paused === true
        ruleId = page.ruleID || ""
        titleDraft = page.title || ""
        noteDraft = page.note || ""
        sourceDraft = page.source || ""
        kind = page.kind || "Every day"
        kinds = page.kinds || []
        days = page.weekdays || []
        monthDay = page.monthDay || 1
        shortMonth = page.shortMonth || "lastDay"
        season = page.season || "greatLent"
        seasons = page.seasons || []
        onceDate = page.onceDate || ""
        hasTime = page.hasTime === true
        hour = page.hour
        minute = page.minute
        reminders = page.reminders !== false
        leadChoices = page.leads || []
        fatherName = page.fatherName || ""
        givenByPriest = page.givenByPriest === true
        scope = page.scope || "wholeSeries"
        scopes = page.scopes || []
    }

    function selectedWeekdays() {
        const raw = []
        for (let index = 0; index < days.length; index++) if (days[index].selected) raw.push(days[index].raw)
        return raw
    }

    function selectedLeads() {
        const raw = []
        for (let index = 0; index < leadChoices.length; index++) {
            if (leadChoices[index].selected) raw.push(leadChoices[index].raw)
        }
        return raw
    }

    function save() {
        bridge.saveRule({
            "title": titleDraft,
            "note": noteDraft,
            "source": sourceDraft,
            "kind": kind,
            "weekdays": selectedWeekdays(),
            "monthDay": monthDay,
            "shortMonth": shortMonth,
            "season": season,
            "onceDate": onceDate,
            "hasTime": hasTime,
            "hour": hour,
            "minute": minute,
            "reminders": reminders,
            "leads": selectedLeads(),
            "givenByPriest": givenByPriest,
            "scope": scope
        })
    }

    Component.onCompleted: load()
    Connections {
        target: bridge
        function onChanged() { if (bridge.editorPage.token !== form.loadedToken) form.load() }
    }

    Flickable {
        id: editorScroll
        objectName: "editor-scroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: column
            width: parent.width - 48
            x: 24
            spacing: 10
            topPadding: 16
            bottomPadding: 24

            Label { text: "What is it?"; color: form.muted; font.pixelSize: 13 }
            TextField {
                objectName: "editor-title"
                width: parent.width
                text: form.titleDraft
                color: form.parchment
                font.pixelSize: 14
                background: Rectangle { color: "#1c1e26"; radius: 5 }
                onTextChanged: form.titleDraft = text
            }

            Label { text: "How often?"; color: form.muted; font.pixelSize: 13 }
            ComboBox {
                objectName: "editor-kind"
                width: parent.width
                model: form.kinds
                currentIndex: Math.max(0, form.kinds.indexOf(form.kind))
                onActivated: function(index) { form.kind = form.kinds[index] }
            }

            Row {
                visible: form.kind === "Certain weekdays"
                spacing: 4
                Repeater {
                    model: form.days
                    delegate: CheckBox {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        checked: modelData.selected
                        onToggled: {
                            const next = form.days.slice()
                            next[index] = {"raw": modelData.raw, "label": modelData.label, "selected": checked}
                            form.days = next
                        }
                    }
                }
            }

            Row {
                visible: form.kind === "Once a month"
                spacing: 8
                ComboBox {
                    model: 31
                    currentIndex: Math.max(0, form.monthDay - 1)
                    onActivated: function(index) { form.monthDay = index + 1 }
                }
                ComboBox {
                    model: ["Use the last day", "Skip a short month"]
                    currentIndex: form.shortMonth === "skip" ? 1 : 0
                    onActivated: function(index) { form.shortMonth = index === 1 ? "skip" : "lastDay" }
                }
            }

            ComboBox {
                visible: form.kind === "Through a fasting season"
                width: parent.width
                model: form.seasons.map(function(item) { return item.name })
                currentIndex: {
                    const ids = form.seasons.map(function(item) { return item.id })
                    return Math.max(0, ids.indexOf(form.season))
                }
                onActivated: function(index) { if (form.seasons[index]) form.season = form.seasons[index].id }
            }

            Label {
                visible: form.kind === "Just one day"
                text: form.onceDate.length > 0 ? ("On " + form.onceDate + ".") : "On the selected day."
                color: form.faint
                font.pixelSize: 13
            }

            CheckBox {
                id: timeBox
                objectName: "editor-time"
                text: "At a set time"
                checked: form.hasTime
                onToggled: form.hasTime = checked
            }
            Row {
                visible: form.hasTime
                spacing: 8
                ComboBox {
                    objectName: "editor-hour"
                    model: 24
                    currentIndex: form.hour
                    onActivated: function(index) { form.hour = index }
                }
                ComboBox {
                    objectName: "editor-minute"
                    model: 60
                    currentIndex: form.minute
                    onActivated: function(index) { form.minute = index }
                }
            }
            Label {
                visible: !form.hasTime
                width: parent.width
                text: "It runs all day, and reminders are spread across the waking hours."
                color: form.faint
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            CheckBox {
                text: "Remind me"
                checked: form.reminders
                onToggled: form.reminders = checked
            }
            Column {
                visible: form.reminders && form.hasTime
                spacing: 2
                Repeater {
                    model: form.leadChoices
                    delegate: CheckBox {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        checked: modelData.selected
                        onToggled: {
                            const next = form.leadChoices.slice()
                            next[index] = {"raw": modelData.raw, "label": modelData.label, "selected": checked}
                            form.leadChoices = next
                        }
                    }
                }
            }

            Label { text: "A note, if it helps"; color: form.muted; font.pixelSize: 13 }
            TextField {
                objectName: "editor-note"
                width: parent.width
                text: form.noteDraft
                color: form.parchment
                font.pixelSize: 14
                background: Rectangle { color: "#1c1e26"; radius: 5 }
                onTextChanged: form.noteDraft = text
            }

            Label { text: "Who suggested it?"; color: form.muted; font.pixelSize: 13 }
            TextField {
                objectName: "editor-source"
                width: parent.width
                visible: form.fatherName.length === 0 || !form.givenByPriest
                text: form.sourceDraft
                color: form.parchment
                font.pixelSize: 14
                background: Rectangle { color: "#1c1e26"; radius: 5 }
                onTextChanged: { if (visible) form.sourceDraft = text }
            }
            CheckBox {
                objectName: "editor-father"
                visible: form.fatherName.length > 0
                text: "Given to me by " + form.fatherName
                checked: form.givenByPriest
                onToggled: form.givenByPriest = checked
            }
            Label {
                width: parent.width
                text: "Months from now this is how you will remember where a rule came from."
                color: form.faint
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            ComboBox {
                visible: form.scopes.length > 0
                objectName: "editor-scope"
                width: parent.width
                model: form.scopes.map(function(item) { return item.name })
                currentIndex: {
                    const ids = form.scopes.map(function(item) { return item.id })
                    return Math.max(0, ids.indexOf(form.scope))
                }
                onActivated: function(index) { if (form.scopes[index]) form.scope = form.scopes[index].id }
            }

            Row {
                spacing: 16
                Label {
                    objectName: "editor-save"
                    text: "Save"
                    color: form.titleDraft.trim().length === 0 ? form.faint : form.gold
                    font.pixelSize: 14
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: form.titleDraft.trim().length > 0
                        onClicked: form.save()
                    }
                }
                Label {
                    objectName: "editor-pause"
                    visible: !form.isNew
                    text: form.paused ? "Resume" : "Pause"
                    color: form.muted
                    font.pixelSize: 14
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: form.paused ? bridge.resumeRule(form.ruleId) : bridge.pauseRule(form.ruleId)
                    }
                }
                Label {
                    visible: !form.isNew
                    text: "Just this day"
                    color: form.muted
                    font.pixelSize: 13
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: bridge.removeRule(form.ruleId, "thisDay") }
                }
                Label {
                    visible: !form.isNew
                    text: "This day and after"
                    color: form.muted
                    font.pixelSize: 13
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: bridge.removeRule(form.ruleId, "thisAndFuture") }
                }
                Label {
                    objectName: "editor-remove-whole"
                    visible: !form.isNew
                    text: "The whole rule"
                    color: form.muted
                    font.pixelSize: 13
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: bridge.removeRule(form.ruleId, "wholeSeries") }
                }
            }
        }
        EdgeFade {
            y: editorScroll.contentY
            width: editorScroll.width
            height: editorScroll.height
            z: 8
        }
    }
}
