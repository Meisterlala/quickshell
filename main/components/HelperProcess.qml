import "../services"
import QtQuick
import Quickshell
import Quickshell.Io

// Shared transport and lifecycle for Go-backed widgets. A cache miss is retried
// after the independent build supervisor finishes; no action ran on that miss.
Scope {
    id: root
    required property string helper
    readonly property bool running: active
    readonly property string outputText: collectedOutput.text
    readonly property string errorText: launchError || collectedErrors.text
    property bool active: false
    property bool waitingForBuild: false
    property var pendingArgs: []
    property string launchError: ""
    signal output(string text)
    signal exited(int exitCode)

    function run(args) {
        if (active)
            return false;
        pendingArgs = (args || []).slice();
        launchError = "";
        active = true;
        if (HelperBuild.ready)
            start();
        else
            waitingForBuild = true;
        return true;
    }

    function start() {
        waitingForBuild = false;
        process.exec(HelperBuild.command(helper, pendingArgs));
        // Process does not emit exited when it cannot start.
        Qt.callLater(() => {
            if (active && !waitingForBuild && !process.running) {
                launchError = "Cannot start the Go helper wrapper.";
                finish(-1);
            }
        });
    }

    function finish(code) {
        if (!active)
            return;
        active = false;
        waitingForBuild = false;
        exited(code);
    }

    function cancel() {
        active = false;
        waitingForBuild = false;
        process.running = false;
    }

    Connections {
        target: HelperBuild
        function onReadyChanged() {
            if (HelperBuild.ready && root.active && root.waitingForBuild)
                root.start();
        }
        function onStateChanged() {
            if (HelperBuild.state === "error" && root.waitingForBuild) {
                root.launchError = HelperBuild.message || "Go helper unavailable.";
                root.finish(75);
            }
        }
    }

    Process {
        id: process
        stdout: StdioCollector {
            id: collectedOutput
            onStreamFinished: {
                if (root.active && text.trim().length > 0)
                    root.output(text);
            }
        }
        stderr: StdioCollector {
            id: collectedErrors
        }
        onExited: code => {
            if (!root.active)
                return;
            if (code === 75) {
                root.waitingForBuild = true;
                HelperBuild.retry();
            } else {
                root.finish(code);
            }
        }
    }
}
