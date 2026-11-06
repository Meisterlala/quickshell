// Month grid adapted from Linuxury/nebula-shell (MIT).
// Source and full license: ../licenses/nebula-shell-MIT.txt
pragma ComponentBehavior: Bound

import ".."
import QtQuick

Column {
    id: root

    required property date today
    property date viewMonth: new Date(today.getFullYear(), today.getMonth(), 1)
    property var dayCounts: ({})
    property string selectedDay: ""
    signal dayClicked(string day)
    readonly property string monthKey: Qt.formatDate(viewMonth, "yyyy-MM")
    readonly property var cells: {
        const first = new Date(viewMonth.getFullYear(), viewMonth.getMonth(), 1);
        const offset = (first.getDay() + 6) % 7; // Monday first.
        const days = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
        const result = [];
        const cellCount = Math.ceil((offset + days) / 7) * 7;
        for (let i = 0; i < cellCount; ++i)
            result.push(i >= offset && i < offset + days ? i - offset + 1 : 0);
        return result;
    }

    function shiftMonth(delta) {
        viewMonth = new Date(viewMonth.getFullYear(), viewMonth.getMonth() + delta, 1);
    }

    function showToday() {
        viewMonth = new Date(today.getFullYear(), today.getMonth(), 1);
    }

    function dateKey(day) {
        return Qt.formatDate(new Date(viewMonth.getFullYear(), viewMonth.getMonth(), day), "yyyy-MM-dd");
    }

    spacing: 6

    Theme {
        id: theme
    }

    Row {
        width: parent.width
        spacing: 6

        Repeater {
            model: ["previous", "month", "today", "next"]

            Rectangle {
                required property string modelData
                readonly property bool isTitle: modelData === "month"
                width: isTitle ? root.width - 32 * 2 - 56 - 18 : modelData === "today" ? 56 : 32
                height: 28
                radius: 8
                color: isTitle ? "transparent" : headerMouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.7)
                Accessible.role: isTitle ? Accessible.StaticText : Accessible.Button
                Accessible.name: modelData === "previous" ? "Previous month" : modelData === "next" ? "Next month" : modelData === "today" ? "Today" : title.text
                Accessible.onPressAction: headerMouse.clicked(null)

                Text {
                    id: title
                    anchors.centerIn: parent
                    text: parent.modelData === "previous" ? "‹" : parent.modelData === "next" ? "›" : parent.modelData === "today" ? "Today" : Qt.formatDate(root.viewMonth, "MMMM yyyy")
                    color: theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: parent.isTitle ? 16 : parent.modelData === "today" ? 12 : 24
                    font.bold: parent.isTitle
                }

                MouseArea {
                    id: headerMouse
                    anchors.fill: parent
                    enabled: !parent.isTitle
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (parent.modelData === "today")
                            root.showToday();
                        else
                            root.shiftMonth(parent.modelData === "previous" ? -1 : 1);
                    }
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: 3
        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            Text {
                required property string modelData
                text: modelData
                width: (root.width - 18) / 7
                horizontalAlignment: Text.AlignHCenter
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 12
            }
        }
    }

    Grid {
        columns: 7
        spacing: 3
        Repeater {
            model: root.cells
            Item {
                id: dayCell
                required property int modelData
                readonly property bool isToday: modelData > 0 && root.dateKey(modelData) === Qt.formatDate(root.today, "yyyy-MM-dd")
                readonly property bool isSelected: modelData > 0 && root.dateKey(modelData) === root.selectedDay
                objectName: modelData > 0 ? "calendarDay_" + root.dateKey(modelData) : ""
                width: (root.width - 18) / 7
                height: 28
                Accessible.role: Accessible.Button
                Accessible.name: modelData > 0 ? root.dateKey(modelData) + (isToday ? ", today" : "") : ""
                Accessible.checkable: modelData > 0
                Accessible.checked: isSelected
                Accessible.onPressAction: {
                    if (modelData > 0)
                        root.dayClicked(root.dateKey(modelData));
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 8
                    color: dayCell.isSelected ? theme.sky : dayCell.isToday ? theme.rosewater : dayMouse.containsMouse ? theme.alpha(theme.surface2, 0.6) : "transparent"
                    border.width: dayCell.isSelected && dayCell.isToday ? 1 : 0
                    border.color: theme.rosewater
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -2
                    text: parent.modelData || ""
                    color: dayCell.isToday || dayCell.isSelected ? theme.base : theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: 13
                    font.bold: dayCell.isToday || dayCell.isSelected
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: 3
                    height: 3
                    radius: 1.5
                    color: dayCell.isToday || dayCell.isSelected ? theme.base : theme.sky
                    visible: parent.modelData > 0 && (root.dayCounts[root.dateKey(parent.modelData)] || 0) > 0
                }

                MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    enabled: dayCell.modelData > 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dayClicked(root.dateKey(dayCell.modelData))
                }
            }
        }
    }
}
