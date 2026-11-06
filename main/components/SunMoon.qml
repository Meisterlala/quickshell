import ".."
import "../services"
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property date today
    property var astronomy: ({})
    readonly property real now: today.getTime() / 1000
    readonly property bool hasTimes: astronomy.sunrise !== undefined && astronomy.sunset !== undefined
    readonly property bool daylight: hasTimes ? now >= astronomy.sunrise && now < astronomy.sunset : astronomy.state === "Midnight sun"
    readonly property real progress: {
        if (!hasTimes)
            return 0.5;
        if (daylight)
            return Math.max(0, Math.min(1, (now - astronomy.sunrise) / (astronomy.sunset - astronomy.sunrise)));
        const start = now < astronomy.sunrise ? (astronomy.previousSunset || astronomy.sunset - 86400) : astronomy.sunset;
        const end = now < astronomy.sunrise ? astronomy.sunrise : (astronomy.nextSunrise || astronomy.sunrise + 86400);
        return Math.max(0, Math.min(1, (now - start) / (end - start)));
    }
    property real animatedProgress: progress
    Behavior on animatedProgress {
        NumberAnimation {
            duration: 1200
        }
    }
    onAnimatedProgressChanged: sky.requestPaint()
    readonly property string dateKey: Qt.formatDate(today, "yyyy-MM-dd")
    implicitHeight: 54
    visible: HelperBuild.ready
    onDateKeyChanged: Qt.callLater(refresh)
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(refresh);
            sky.requestPaint();
        }
    }
    onDaylightChanged: sky.requestPaint()
    onAstronomyChanged: sky.requestPaint()
    Component.onCompleted: Qt.callLater(refresh)

    function refresh() {
        if (visible && HelperBuild.ready && !reader.running)
            reader.run();
    }
    function timeLabel(value) {
        return value === undefined ? "—" : Qt.formatDateTime(new Date(value * 1000), "hh:mm");
    }
    Theme {
        id: theme
    }
    HelperProcess {
        id: reader
        helper: "astronomy"
        onOutput: text => {
            try {
                root.astronomy = JSON.parse(text);
            } catch (error) {
                root.astronomy = {
                    error: "Astronomy unavailable"
                };
            }
        }
    }
    Timer {
        interval: root.astronomy.moonName ? 3600000 : 60000
        running: root.visible
        repeat: true
        onTriggered: root.refresh()
    }

    Canvas {
        id: sky
        width: root.width
        height: root.height
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onAvailableChanged: {
            if (available)
                requestPaint();
        }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, base = height - 8, rx = width / 2 - 20, ry = Math.max(0, base - 17);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = "#242431";
            ctx.beginPath();
            ctx.moveTo(10, base);
            ctx.lineTo(width - 10, base);
            ctx.stroke();
            ctx.setLineDash([3, 5]);
            ctx.beginPath();
            for (let i = 0; i <= 80; i++) {
                const a = Math.PI * (1 - i / 80);
                const x = cx + rx * Math.cos(a), y = base - ry * Math.sin(a);
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
            if (!root.astronomy.moonName)
                return;
            const angle = Math.PI * (1 - root.animatedProgress);
            const x = cx + rx * Math.cos(angle), y = base - ry * Math.sin(angle);
            const radius = 9;
            ctx.fillStyle = root.daylight ? theme.yellow : theme.text;
            ctx.beginPath();
            ctx.arc(x, y, radius, 0, 2 * Math.PI);
            ctx.fill();
            if (root.daylight) {
                ctx.strokeStyle = theme.yellow;
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4;
                    ctx.beginPath();
                    ctx.moveTo(x + Math.cos(a) * 12, y + Math.sin(a) * 12);
                    ctx.lineTo(x + Math.cos(a) * 15, y + Math.sin(a) * 15);
                    ctx.stroke();
                }
            } else {
                // Trace the unlit portion with a spherical terminator.
                const phase = root.astronomy.phase || 0;
                const waxing = phase < 0.5;
                const terminator = Math.cos(2 * Math.PI * phase);
                ctx.fillStyle = theme.surface0;
                ctx.beginPath();
                for (let i = 0; i <= 40; i++) {
                    const a = -Math.PI / 2 + i * Math.PI / 40;
                    const px = x + (waxing ? -1 : 1) * radius * Math.cos(a);
                    const py = y + radius * Math.sin(a);
                    if (i === 0)
                        ctx.moveTo(px, py);
                    else
                        ctx.lineTo(px, py);
                }
                for (let i = 40; i >= 0; i--) {
                    const a = -Math.PI / 2 + i * Math.PI / 40;
                    ctx.lineTo(x + (waxing ? 1 : -1) * terminator * radius * Math.cos(a), y + radius * Math.sin(a));
                }
                ctx.closePath();
                ctx.fill();
            }
        }
    }
    Text {
        y: 0
        text: (root.daylight ? "↑ " : "↓ ") + root.timeLabel(root.daylight ? root.astronomy.sunrise : root.astronomy.sunset)
        color: theme.subtext0
        font.family: theme.fontFamily
        font.pixelSize: 11
    }
    Text {
        y: 0
        anchors.right: root.right
        text: (root.daylight ? "↓ " : "↑ ") + root.timeLabel(root.daylight ? root.astronomy.sunset : root.astronomy.sunrise)
        color: theme.subtext0
        font.family: theme.fontFamily
        font.pixelSize: 11
    }
}
