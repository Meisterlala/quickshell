pragma ComponentBehavior: Bound

import ".."
import "../components"
import "../services"
import "../components/CalendarDates.js" as CalendarDates
import QtQuick

PopupSurface {
    id: root

    required property date today
    property var events: []
    property var monthEvents: []
    property string selectedDay: ""
    property var selectedEvents: []
    readonly property var shownEvents: selectedDay ? selectedEvents : events
    property var dayCounts: ({})
    property string errorText: ""
    property string warningText: ""
    property bool loaded: false
    property bool ready: false
    property bool refreshPending: false
    property string requestedMonth: ""
    property string requestedDay: ""

    function selectDay(day) {
        selectedDay = selectedDay === day ? "" : day;
        selectedEvents = selectedDay ? CalendarDates.eventsForDay(monthEvents, selectedDay) : [];
        refresh();
    }

    implicitHeight: content.implicitHeight + 28

    function refresh() {
        if (!ready || !HelperBuild.ready)
            return;
        if (reader.running) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        requestedMonth = month.monthKey;
        requestedDay = selectedDay;
        const args = ["--month", requestedMonth];
        if (requestedDay)
            args.push("--day", requestedDay);
        reader.run(args);
    }

    function applyOutput(output) {
        if (requestedMonth !== month.monthKey)
            return;
        try {
            const data = JSON.parse(output);
            events = data.events || [];
            monthEvents = data.monthEvents || [];
            if (requestedDay === selectedDay)
                selectedEvents = data.dayEvents || [];
            dayCounts = data.dayCounts || ({});
            errorText = data.error || "";
            warningText = data.warning || "";
            loaded = true;
        } catch (error) {
            errorText = "Couldn't read Thunderbird calendars";
        }
    }

    function eventTime(event) {
        if (event.allDay)
            return event.kind === "task" ? "Task · All day" : "All day";
        const start = Qt.formatDateTime(new Date(event.start), "hh:mm");
        if (event.kind === "task")
            return "Task · " + start;
        return start + "–" + Qt.formatDateTime(new Date(event.end), "hh:mm");
    }

    Component.onCompleted: {
        ready = true;
        refresh();
    }

    Connections {
        target: HelperBuild
        function onReadyChanged() {
            if (HelperBuild.ready)
                root.refresh();
        }
    }

    Theme {
        id: theme
    }

    Timer {
        interval: 60000
        running: root.visible && HelperBuild.ready
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: monthDebounce
        interval: 100
        onTriggered: root.refresh()
    }

    HelperProcess {
        id: reader
        helper: "calendar"
        onOutput: text => root.applyOutput(text)
        onExited: exitCode => {
            if (exitCode !== 0 && !root.errorText)
                root.errorText = "Calendar reader failed";
            if (root.refreshPending)
                Qt.callLater(root.refresh);
        }
    }

    Column {
        id: content
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 8

        Row {
            width: parent.width
            spacing: 12

            Column {
                id: dateAndTime
                width: Math.max(headerTime.width, dateLabel.implicitWidth)
                spacing: 8

                Text {
                    id: dateLabel
                    text: Qt.formatDateTime(root.today, "dddd, dd.MM.yyyy")
                    color: theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    id: headerTime
                    width: 154
                    height: 54
                    text: Qt.formatDateTime(root.today, "hh:mm")
                    color: theme.rosewater
                    font.family: theme.fontFamily
                    font.pixelSize: 48
                    font.bold: true
                    fontSizeMode: Text.Fit
                    verticalAlignment: Text.AlignVCenter
                }
            }

            SunMoon {
                width: parent.width - dateAndTime.width - parent.spacing
                height: dateAndTime.height
                today: root.today
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: theme.alpha(theme.text, 0.12)
        }

        CalendarMonth {
            id: month
            width: parent.width
            today: root.today
            dayCounts: HelperBuild.ready ? root.dayCounts : ({})
            selectedDay: root.selectedDay
            onDayClicked: day => root.selectDay(day)
            onMonthKeyChanged: {
                root.monthEvents = [];
                root.dayCounts = ({});
                if (!root.selectedDay)
                    root.loaded = false;
                monthDebounce.restart();
            }
        }

        Rectangle {
            visible: HelperBuild.ready
            width: parent.width
            height: 1
            color: theme.alpha(theme.text, 0.12)
        }

        Row {
            visible: HelperBuild.ready
            width: parent.width
            height: 26
            Text {
                width: parent.width - rangeLabel.implicitWidth
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: root.selectedDay ? Qt.formatDate(new Date(root.selectedDay + "T12:00:00"), "ddd, dd MMM") : "Upcoming"
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }
            Text {
                id: rangeLabel
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: root.selectedDay ? "" : "Next 30 days"
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 12
            }
        }

        Text {
            width: parent.width
            visible: HelperBuild.ready && (root.errorText.length > 0 || root.warningText.length > 0)
            text: root.errorText || root.warningText
            color: root.errorText ? theme.red : theme.yellow
            font.family: theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        Text {
            width: parent.width
            visible: HelperBuild.ready && root.shownEvents.length === 0
            text: root.errorText ? "Calendar unavailable" : !root.loaded ? "Loading Thunderbird calendars…" : root.selectedDay ? "No events on this day" : "No upcoming events"
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        ListView {
            id: agenda
            width: parent.width
            height: Math.min(contentHeight, 400)
            visible: HelperBuild.ready && count > 0
            clip: true
            spacing: 6
            model: root.shownEvents
            onModelChanged: positionViewAtBeginning()
            boundsBehavior: Flickable.StopAtBounds
            section.property: root.selectedDay ? "" : "date"
            section.criteria: ViewSection.FullString
            section.delegate: Text {
                required property string section
                width: agenda.width
                height: 24
                text: Qt.formatDate(new Date(section + "T12:00:00"), "ddd, dd MMM")
                verticalAlignment: Text.AlignVCenter
                color: theme.rosewater
                font.family: theme.fontFamily
                font.pixelSize: 13
            }

            delegate: Rectangle {
                id: eventCard
                required property var modelData
                width: agenda.width
                implicitHeight: details.implicitHeight + 12
                radius: 8
                color: theme.alpha(theme.surface0, 0.65)

                Rectangle {
                    x: 0
                    y: 6
                    width: 3
                    height: parent.height - 12
                    radius: 1
                    color: eventCard.modelData.color || theme.sky
                }

                Column {
                    id: details
                    x: 10
                    y: 6
                    width: parent.width - 20
                    spacing: 3

                    Text {
                        width: parent.width
                        text: eventCard.modelData.title
                        color: theme.text
                        font.family: theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }

                    Text {
                        width: parent.width
                        text: root.eventTime(eventCard.modelData) + " · " + eventCard.modelData.calendar
                        color: theme.subtext0
                        font.family: theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: eventCard.modelData.location
                        color: theme.subtext0
                        font.family: theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }
}
