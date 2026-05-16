import "../components"
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

ClippingRectangle {
    id: root

    required property var barWindow
    property var ipc: null
    property bool moduleVisible: true
    property int interval: 15000
    property string moduleName: "habits"
    property string command: "/home/misti/.config/quickshell/main/scripts/habits_quickshell.py"
    property string text: ""
    property string state: "pending"
    property string date: ""
    property string errorText: ""
    property var summary: ({})
    property var habits: []
    property var activeEvents: []
    property var notifications: []
    property var policies: []
    property var deadlines: []
    property var contracts: []
    property var events: []
    property var counts: ({})
    property bool popupPinned: false
    property bool habitsCollapsed: false
    property bool activeEventsCollapsed: false
    property bool notificationsCollapsed: false
    property bool thingsCollapsed: false
    property bool contractsCollapsed: false
    property bool loggedEventsCollapsed: false
    property bool previousAllHabitsDone: false
    property string actionError: ""
    property string pendingAction: ""
    signal alternativeModeRequested()
    readonly property bool popupVisible: visible && (mouse.containsMouse || popupPinned)
    readonly property bool hasError: state === "error" || errorText.length > 0
    readonly property string accent: hasError ? theme.red : state === "done" ? theme.green : state === "warning" ? theme.yellow : state === "active" ? theme.sky : theme.red
    readonly property string accentSoft: theme.alpha(String(accent), 0.24)

    function refresh() {
        if (!moduleVisible)
            return;
        refreshRunner.exec(["/usr/bin/python3", command]);
    }

    function runAction(args, actionKey) {
        pendingAction = actionKey;
        actionError = "";
        actionRunner.exec(["/usr/bin/python3", command].concat(args));
    }

    function toggleApp() {
        launcher.exec(["/usr/bin/python3", command, "--toggle-app"]);
    }

    function toggleHabit(habit) {
        if (!date || !habit || !habit.id)
            return;
        const nextStatus = habit.done ? "missed" : "done";
        runAction(["--set-habit", date, String(habit.id), nextStatus], `habit:${habit.id}`);
    }

    function stopEvent(eventItem) {
        if (!date || !eventItem || !eventItem.id)
            return;
        runAction(["--stop-event", date, String(eventItem.id)], `event:${eventItem.id}`);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No Habits output";
            state = "error";
            text = "?/?";
            return;
        }

        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            text = String(parsed.text || "?/?");
            state = String(parsed.state || "pending");
            date = String(parsed.date || "");
            errorText = String(parsed.error || "");
            summary = parsed.summary || ({});
            habits = parsed.habits || [];
            activeEvents = parsed.active_events || [];
            notifications = parsed.notifications || [];
            policies = parsed.policies || [];
            deadlines = parsed.deadlines || [];
            contracts = parsed.contracts || [];
            events = parsed.events || [];
            counts = parsed.counts || ({});
            const allDone = habits.length > 0 && habits.every(habit => Boolean(habit.done));
            if (allDone && !previousAllHabitsDone)
                habitsCollapsed = true;
            else if (!allDone)
                habitsCollapsed = false;
            previousAllHabitsDone = allDone;
        } catch (error) {
            errorText = trimmed;
            state = "error";
            text = "?/?";
        }
    }

    function formatHeaderMeta() {
        const tier = String(summary.tier || "Unknown");
        const activeCount = activeEvents.length;
        const activeText = activeCount > 0 ? ` · 󰥔 ${activeCount} running` : "";
        return `${date || "today"} · ${tier}${activeText}`;
    }

    function valueColor(value) {
        const numberValue = Number(value || 0);
        if (numberValue > 0)
            return theme.green;
        if (numberValue < 0)
            return theme.red;
        return theme.yellow;
    }

    function scrollList(delta) {
        if (!popupVisible)
            return;
        const maxY = Math.max(0, bodyFlickable.contentHeight - bodyFlickable.height);
        bodyFlickable.contentY = Math.max(0, Math.min(maxY, bodyFlickable.contentY - delta));
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse || popupPinned ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: hasError ? theme.alpha(theme.red, 0.72) : theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && text.length > 0

    Theme {
        id: theme
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width
        radius: 0
        color: root.accentSoft
    }

    Row {
        id: compactContent
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.hasError ? "" : ""
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.hasError ? root.text : `${Number(summary.habits_done || 0)}/${Number(summary.habits_total || 0)}`
            textFormat: Text.PlainText
        }

        CountSegment {
            visible: !root.hasError && Number(root.counts.active_events || 0) > 0
            icon: ""
            value: Number(root.counts.active_events || 0)
            accent: theme.yellow
        }

        CountSegment {
            visible: !root.hasError && Number(root.counts.policies || 0) + Number(root.counts.deadlines || 0) > 0
            icon: "󰄬"
            value: Number(root.counts.policies || 0) + Number(root.counts.deadlines || 0)
            accent: theme.subtext0
        }

        CountSegment {
            visible: !root.hasError && Number(root.counts.notifications || 0) > 0
            icon: ""
            value: Number(root.counts.notifications || 0)
            accent: theme.red
        }
    }

    PopupWindow {
        id: popupWindow

        readonly property int margin: 8
        readonly property int maxPopupHeight: root.barWindow && root.barWindow.screen ? Math.max(260, Math.round((root.barWindow.screen.height - root.barWindow.height - margin * 2) * 0.78)) : 620

        anchor.window: root.barWindow
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, root.mapToItem(null, 0, 0).x + root.width / 2 - width / 2)) : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + margin : root.height + margin
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        implicitWidth: 700
        implicitHeight: Math.min(maxPopupHeight, popupContent.implicitHeight + 28)
        color: "transparent"
        visible: root.barWindow && root.popupVisible

        PopupSurface {
            anchors.fill: parent
            clip: true
            color: theme.alpha(theme.surface1, 0.97)

            Column {
                id: popupContent
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        anchors.top: parent.top
                        color: root.accent
                        font.family: theme.fontFamily
                        font.pixelSize: theme.barFontPixelSize + 8
                        text: root.hasError ? "" : ""
                    }

                    Column {
                        width: parent.width - 42
                        spacing: 2

                        Text {
                            width: parent.width
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize + 5
                            font.bold: true
                            text: root.hasError ? "Habits unavailable" : `Habits Today · ${Number(summary.habits_done || 0)}/${Number(summary.habits_total || 0)} done`
                        }

                        Text {
                            width: parent.width
                            color: theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            elide: Text.ElideRight
                            text: root.hasError ? "Check API/config status" : root.formatHeaderMeta()
                        }
                    }
                }

                Row {
                    visible: !root.hasError
                    width: parent.width
                    spacing: 8

                    StatChip {
                        label: "Today"
                        value: String(summary.points_today_label || "0")
                        accent: root.valueColor(summary.points_today)
                    }

                    StatChip {
                        label: "Rolling"
                        value: `${String(summary.recent_points_label || "0")}${summary.rolling_delta_label ? " (" + summary.rolling_delta_label + ")" : ""}`
                        accent: root.valueColor(summary.recent_points)
                    }

                    StatChip {
                        label: "Banked"
                        value: String(summary.banked_points_label || "0")
                        accent: root.valueColor(summary.banked_points)
                    }

                    StatChip {
                        label: "Punish"
                        value: String(summary.punishment_points_label || "0")
                        accent: root.valueColor(-Number(summary.punishment_points || 0))
                    }

                    StatChip {
                        visible: String(summary.weight_label || "").length > 0
                        label: "Weight"
                        value: String(summary.weight_label || "")
                        accent: theme.sky
                    }
                }

                Text {
                    visible: root.hasError
                    width: parent.width
                    color: theme.red
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    wrapMode: Text.Wrap
                    text: root.errorText
                }

                Text {
                    visible: root.actionError.length > 0
                    width: parent.width
                    color: theme.red
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    wrapMode: Text.Wrap
                    text: root.actionError
                }

                Flickable {
                    id: bodyFlickable
                    visible: !root.hasError
                    width: parent.width
                    height: Math.max(0, Math.min(bodyColumn.implicitHeight, popupWindow.maxPopupHeight - y - 20))
                    contentWidth: width
                    contentHeight: bodyColumn.implicitHeight
                    clip: true

                    Column {
                        id: bodyColumn
                        width: parent.width
                        spacing: 10

                        SectionHeader {
                            visible: root.activeEvents.length > 0
                            title: "Running Now"
                            count: root.activeEvents.length
                            accent: theme.yellow
                            collapsed: root.activeEventsCollapsed
                            onToggled: root.activeEventsCollapsed = !root.activeEventsCollapsed
                        }

                        Repeater {
                            model: root.activeEventsCollapsed ? [] : root.activeEvents
                            EventCard {
                                required property var modelData
                                width: bodyColumn.width
                                eventItem: modelData
                                busy: root.pendingAction === `event:${String(modelData.id || "")}`
                                onStopRequested: root.stopEvent(modelData)
                            }
                        }

                        SectionHeader {
                            visible: root.notifications.length > 0
                            title: "Persistent Notifications"
                            count: root.notifications.length
                            accent: theme.red
                            collapsed: root.notificationsCollapsed
                            onToggled: root.notificationsCollapsed = !root.notificationsCollapsed
                        }

                        Repeater {
                            model: root.notificationsCollapsed ? [] : root.notifications
                            NotificationCard {
                                required property var modelData
                                width: bodyColumn.width
                                notification: modelData
                            }
                        }

                        SectionHeader {
                            title: "Daily Habits"
                            count: root.habits.length
                            accent: theme.sky
                            collapsed: root.habitsCollapsed
                            onToggled: root.habitsCollapsed = !root.habitsCollapsed
                        }

                        Repeater {
                            model: root.habitsCollapsed ? [] : root.habits
                            HabitRow {
                                required property var modelData
                                width: bodyColumn.width
                                habit: modelData
                                busy: root.pendingAction === `habit:${String(modelData.id || "")}`
                                onToggleRequested: root.toggleHabit(modelData)
                            }
                        }

                        SectionHeader {
                            visible: root.deadlines.length + root.policies.length > 0
                            title: "Things To Do"
                            count: root.deadlines.length + root.policies.length
                            accent: theme.yellow
                            collapsed: root.thingsCollapsed
                            onToggled: root.thingsCollapsed = !root.thingsCollapsed
                        }

                        Repeater {
                            model: root.thingsCollapsed ? [] : root.deadlines
                            DeadlineCard {
                                required property var modelData
                                width: bodyColumn.width
                                deadline: modelData
                            }
                        }

                        Repeater {
                            model: root.thingsCollapsed ? [] : root.policies
                            PolicyCard {
                                required property var modelData
                                width: bodyColumn.width
                                policy: modelData
                            }
                        }

                        SectionHeader {
                            visible: root.contracts.length > 0
                            title: "Active Contracts"
                            count: root.contracts.length
                            accent: theme.sky
                            collapsed: root.contractsCollapsed
                            onToggled: root.contractsCollapsed = !root.contractsCollapsed
                        }

                        Repeater {
                            model: root.contractsCollapsed ? [] : root.contracts
                            SimpleCard {
                                required property var modelData
                                width: bodyColumn.width
                                title: String(modelData.name || "Contract")
                                body: String(modelData.description || "")
                                accent: theme.sky
                            }
                        }

                        SectionHeader {
                            visible: root.events.length > 0
                            title: "Logged Today"
                            count: root.events.length
                            accent: theme.green
                            collapsed: root.loggedEventsCollapsed
                            onToggled: root.loggedEventsCollapsed = !root.loggedEventsCollapsed
                        }

                        Repeater {
                            model: root.loggedEventsCollapsed ? [] : root.events
                            SimpleCard {
                                required property var modelData
                                width: bodyColumn.width
                                title: `${String(modelData.name || "Event")} · ${String(modelData.amount_label || "")}`
                                body: String(modelData.points_label || "")
                                accent: theme.green
                            }
                        }
                    }
                }
            }
        }
    }

    component StatChip: Rectangle {
        required property string label
        required property string value
        required property string accent

        implicitWidth: chipColumn.implicitWidth + 18
        implicitHeight: 42
        radius: 10
        color: theme.alpha(String(accent), 0.16)
        border.color: theme.alpha(String(accent), 0.35)
        border.width: 1

        Column {
            id: chipColumn
            anchors.centerIn: parent
            spacing: 1
            Text {
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 10
                text: label
            }
            Text {
                color: accent
                font.family: theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                text: value
            }
        }
    }

    component CountSegment: Row {
        required property string icon
        required property int value
        required property string accent

        spacing: 3

        Text {
            width: 16
            anchors.verticalCenter: parent.verticalCenter
            color: accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            horizontalAlignment: Text.AlignHCenter
            text: icon
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: String(value)
            textFormat: Text.PlainText
        }
    }

    component SectionHeader: Item {
        id: sectionRoot

        required property string title
        property int count: 0
        required property string accent
        property bool collapsed: false
        signal toggled()

        width: parent ? parent.width : implicitWidth
        height: 22

        Text {
            id: sectionChevron
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            color: accent
            font.family: theme.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            text: sectionRoot.collapsed ? "" : ""
        }

        Text {
            id: sectionTitle
            anchors.left: sectionChevron.right
            anchors.leftMargin: 6
            anchors.right: sectionCount.visible ? sectionCount.left : parent.right
            anchors.rightMargin: sectionCount.visible ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            color: accent
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize + 1
            font.bold: true
            elide: Text.ElideRight
            text: title
        }

        Text {
            id: sectionCount
            visible: count > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: accent
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize + 1
            font.bold: true
            horizontalAlignment: Text.AlignRight
            text: String(count)
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sectionRoot.toggled()
        }
    }

    component HabitRow: Rectangle {
        id: habitRoot
        required property var habit
        property bool busy: false
        signal toggleRequested()

        height: 44
        radius: 10
        color: theme.alpha(habit.done ? theme.green : theme.red, habitMouse.containsMouse ? 0.3 : 0.22)
        border.color: theme.alpha(habit.done ? theme.green : theme.red, 0.55)
        border.width: 1

        Text {
            id: check
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: habit.done ? theme.green : theme.red
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize + 2
            text: habitRoot.busy ? "󰔟" : habit.done ? "󰄲" : "󰄱"
        }

        Text {
            anchors.left: check.right
            anchors.leftMargin: 10
            anchors.right: points.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            elide: Text.ElideRight
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize + 1
            font.bold: !habit.done
            text: String(habit.name || "Habit")
        }

        Text {
            id: points
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: root.valueColor(habit.effective_points)
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            text: String(habit.points_label || "")
        }

        MouseArea {
            id: habitMouse
            anchors.fill: parent
            enabled: !habitRoot.busy
            hoverEnabled: true
            onClicked: habitRoot.toggleRequested()
        }
    }

    component EventCard: Rectangle {
        id: eventRoot
        required property var eventItem
        property bool busy: false
        signal stopRequested()

        height: 58
        radius: 12
        color: theme.alpha(theme.yellow, 0.24)
        border.color: theme.alpha(theme.yellow, 0.6)
        border.width: 1

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: stopButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                color: theme.text
                elide: Text.ElideRight
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize + 1
                font.bold: true
                text: String(eventItem.name || "Running event")
            }
            Text {
                width: parent.width
                color: theme.subtext0
                elide: Text.ElideRight
                font.family: theme.fontFamily
                font.pixelSize: 11
                text: `󰥔 ${String(eventItem.amount_label || "running")} · ${String(eventItem.points_label || "")}`
            }
        }

        ActionButton {
            id: stopButton
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            label: eventRoot.busy ? "..." : "Stop"
            accent: theme.red
            enabled: !eventRoot.busy
            onPressed: eventRoot.stopRequested()
        }
    }

    component NotificationCard: Rectangle {
        required property var notification
        height: notificationColumn.implicitHeight + 18
        radius: 12
        color: theme.alpha(theme.red, 0.2)
        border.color: theme.alpha(theme.red, 0.52)
        border.width: 1

        Column {
            id: notificationColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            spacing: 4
            Text {
                width: parent.width
                color: theme.text
                elide: Text.ElideRight
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize + 1
                font.bold: true
                text: String(notification.title || "Notification")
            }
            Text {
                visible: String(notification.description || "").length > 0
                width: parent.width
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
                text: String(notification.description || "")
            }
            Rectangle {
                visible: Number(notification.progress_max || 0) > 0
                width: parent.width
                height: 6
                radius: 3
                color: theme.alpha(theme.text, 0.12)
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: Math.min(parent.width, parent.width * Number(notification.progress_current || 0) / Math.max(1, Number(notification.progress_max || 1)))
                    color: theme.red
                }
            }
            Text {
                visible: String(notification.progress_label || "").length > 0
                color: theme.overlay1
                font.family: theme.fontFamily
                font.pixelSize: 10
                text: String(notification.progress_label || "")
            }
        }
    }

    component DeadlineCard: SimpleCard {
        required property var deadline
        title: String(deadline.title || "Deadline")
        body: String(deadline.description || "")
        rightLabel: String(deadline.due_label || "")
        accent: Number(deadline.days_until === undefined || deadline.days_until === null ? 99 : deadline.days_until) <= 1 ? theme.red : theme.yellow
    }

    component PolicyCard: Rectangle {
        required property var policy

        height: policyColumn.implicitHeight + 20
        radius: 12
        color: theme.alpha(theme.red, 0.2)
        border.color: theme.alpha(theme.red, 0.52)
        border.width: 1

        Column {
            id: policyColumn
            anchors.left: parent.left
            anchors.right: pointsDelta.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            spacing: 5

            Text {
                width: parent.width
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize + 1
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: String(policy.description || "Policy")
            }

            Text {
                width: parent.width
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: `${String(policy.progress_label || "")} · ${String(policy.message || "")}`
            }
        }

        Text {
            id: pointsDelta
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 76
            color: root.valueColor(policy.points_delta)
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize + 8
            font.bold: true
            horizontalAlignment: Text.AlignRight
            text: String(policy.points_label || "")
        }
    }

    component SimpleCard: Rectangle {
        required property string title
        property string body: ""
        property string rightLabel: ""
        required property string accent

        height: simpleColumn.implicitHeight + 18
        radius: 12
        color: theme.alpha(String(accent), 0.2)
        border.color: theme.alpha(String(accent), 0.52)
        border.width: 1

        Column {
            id: simpleColumn
            anchors.left: parent.left
            anchors.right: simpleRightLabel.visible ? simpleRightLabel.left : parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: simpleRightLabel.visible ? 12 : 12
            spacing: 3
            Text {
                width: parent.width
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize + 1
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: title
            }
            Text {
                visible: body.length > 0
                width: parent.width
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: body
            }
        }

        Text {
            id: simpleRightLabel
            visible: rightLabel.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 100
            color: accent
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize + 2
            font.bold: true
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            maximumLineCount: 2
            text: rightLabel
        }
    }

    component ActionButton: Rectangle {
        id: buttonRoot
        required property string label
        required property string accent
        signal pressed()

        implicitWidth: buttonText.implicitWidth + 20
        implicitHeight: 30
        radius: 9
        color: buttonMouse.containsMouse ? theme.alpha(String(accent), 0.32) : theme.alpha(String(accent), 0.2)
        border.color: theme.alpha(String(accent), 0.5)
        border.width: 1

        Text {
            id: buttonText
            anchors.centerIn: parent
            color: buttonRoot.enabled ? buttonRoot.accent : theme.overlay1
            font.family: theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            text: buttonRoot.label
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: buttonRoot.enabled
            hoverEnabled: true
            onClicked: buttonRoot.pressed()
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        z: 10
        onClicked: (event) => {
            if (event.button === Qt.LeftButton)
                root.toggleApp();
            else if (event.button === Qt.RightButton)
                root.popupPinned = !root.popupPinned;
            else if (event.button === Qt.MiddleButton)
                root.alternativeModeRequested();
        }
        onWheel: (wheel) => {
            root.scrollList(wheel.angleDelta.y);
            wheel.accepted = true;
        }
    }

    Timer {
        interval: root.interval
        running: root.moduleVisible && root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: refreshRunner
        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text)
        }
    }

    Process {
        id: actionRunner
        stdout: StdioCollector {
            onStreamFinished: {
                root.pendingAction = "";
                const trimmed = this.text.trim();
                if (trimmed.length > 0)
                    root.actionError = trimmed;
                root.refresh();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const trimmed = this.text.trim();
                if (trimmed.length > 0)
                    root.actionError = trimmed;
            }
        }
    }

    Process {
        id: launcher
    }

    Connections {
        function onRefreshRequested(name) {
            if (name === root.moduleName || name === "all")
                root.refresh();
        }
        target: root.ipc
    }

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();
        else {
            text = "";
            popupPinned = false;
        }
    }
}
