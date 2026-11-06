pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One build supervisor for the entire shell, independent of widget visibility.
Singleton {
    id: root

    property string state: "building"
    property string message: "Preparing Quickshell helpers…"
    property string statusPath: ""
    property string logPath: ""
    property string buildOutput: ""
    property double startedAt: Date.now()
    property int elapsedSeconds: 0
    readonly property string elapsed: elapsedSeconds < 60 ? elapsedSeconds + "s" : Math.floor(elapsedSeconds / 60) + "m " + elapsedSeconds % 60 + "s"
    readonly property bool ready: state === "ready" && !prepare.running && !locate.running
    readonly property bool visible: !ready
    readonly property bool busy: prepare.running || locate.running || state === "building"
    readonly property string wrapper: Quickshell.shellPath("helpers/qs-helper")

    function applyStatus(contents) {
        const lines = contents.split("\n");
        if (!["building", "ready", "error"].includes(lines[0]))
            return;
        message = lines[1] || "";
        logPath = lines[2] || "";
        if (lines[0] === "building" && Number(lines[3]) > 0)
            startedAt = Number(lines[3]) * 1000;
        state = lines[0];
    }

    function retry() {
        if (prepare.running || locate.running)
            return;
        state = "building";
        message = "Checking sources and the cached binary…";
        startedAt = Date.now();
        elapsedSeconds = 0;
        buildOutput = "";
        if (statusPath) {
            startBuild();
        } else {
            locate.exec([wrapper, "--status-path"]);
            Qt.callLater(() => {
                if (!locate.running && !prepare.running && !statusPath && state === "building")
                    setError("Cannot start the Go helper wrapper.");
            });
        }
    }

    function setError(details) {
        message = details;
        state = "error";
    }

    function startBuild() {
        prepare.exec([wrapper, "--prepare"]);
        Qt.callLater(() => {
            if (!prepare.running && state === "building")
                setError("Cannot start the Go helper build.");
        });
    }

    // The wrapper path and invocation contract live in this service only.
    function command(name, args) {
        return [wrapper, "--run", name].concat(args || []);
    }

    FileView {
        id: statusFile
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyStatus(text())
    }

    FileView {
        path: root.visible ? root.logPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const lines = text().trim().split("\n").filter(line => line.trim().length > 0);
            root.buildOutput = lines.slice(-10).join("\n");
        }
        onLoadFailed: root.buildOutput = ""
    }

    Timer {
        interval: 1000
        running: root.state === "building"
        repeat: true
        onTriggered: root.elapsedSeconds = Math.max(0, Math.floor((Date.now() - root.startedAt) / 1000))
    }

    Process {
        id: locate
        stdout: StdioCollector {
            id: locatedPath
        }
        stderr: StdioCollector {
            id: locateErrors
        }
        onExited: code => {
            if (code === 0 && locatedPath.text.trim()) {
                root.statusPath = locatedPath.text.trim();
                root.startBuild();
            } else {
                root.setError(locateErrors.text.trim() || "Cannot start the Go helper wrapper.");
            }
        }
    }

    Process {
        id: prepare
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: buildErrors
        }
        onExited: code => {
            if (code === 0) {
                root.state = "ready";
                root.message = "";
            } else {
                root.setError(buildErrors.text.trim() || "Go helper preparation failed.");
            }
            statusFile.reload();
        }
    }

    Component.onCompleted: retry()
}
