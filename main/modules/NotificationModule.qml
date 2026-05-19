import "../components"
import ".."
import QtQuick
import Quickshell.Io

ModulePill {
    id: root

    property bool moduleVisible: true
    property string onClickCommand: "swaync-client -t -sw"
    property string onRightClickCommand: "swaync-client -d -sw"
    property string onMiddleClickCommand: "swaync-client -C -sw"
    property string currentTooltip: ""
    property string currentClass: "none"

    function classList(value) {
        if (Array.isArray(value))
            return value.map(item => String(item));

        if (value === undefined || value === null || String(value).length === 0)
            return [];

        return [String(value)];
    }

    function decodeEntities(value) {
        return value.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&apos;/g, "'");
    }

    function plainTooltip(value) {
        return decodeEntities(String(value ?? "").replace(/\r/g, "\n").replace(/<[^>]*>/g, "").trim());
    }

    function iconFor(classes) {
        for (const name of classes) {
            if (formatIcons[name] !== undefined)
                return String(formatIcons[name]);
        }

        return formatIcons.none;
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0)
            return ;

        try {
            const parsed = JSON.parse(trimmed);
            const classes = classList(parsed.class || parsed.alt);
            currentClass = classes[0] ?? "none";
            text = iconFor(classes);
            currentTooltip = plainTooltip(parsed.tooltip ?? "");
        } catch (error) {
            currentClass = "error";
            currentTooltip = trimmed;
        }
    }

    function runCommand(commandText) {
        if (commandText.length === 0)
            return ;

        actionRunner.exec(["/usr/bin/sh", "-lc", commandText]);
    }

    text: formatIcons.none
    tooltipText: currentTooltip
    moduleClass: currentClass
    visible: moduleVisible
    backgroundVisible: false
    fontPixelSize: theme.notificationFontPixelSize
    horizontalPadding: 4
    minimumWidth: 26
    readonly property var formatIcons: ({
        "notification": "󱅫",
        "none": "󰂜",
        "dnd-notification": "󰂠",
        "dnd-none": "󰪓",
        "inhibited-notification": "󰂛",
        "inhibited-none": "󰪑",
        "dnd-inhibited-notification": "󰂛",
        "dnd-inhibited-none": "󰪑"
    })
    onClicked: (button) => {
        if (button === Qt.LeftButton)
            runCommand(onClickCommand);

        if (button === Qt.RightButton)
            runCommand(onRightClickCommand);

        if (button === Qt.MiddleButton)
            runCommand(onMiddleClickCommand);

    }

    Theme {
        id: theme
    }

    Process {
        command: ["swaync-client", "-swb"]
        running: root.moduleVisible

        stdout: SplitParser {
            onRead: line => root.applyOutput(line)
        }
    }

    Process {
        id: actionRunner
    }
}
