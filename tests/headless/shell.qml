// Copied into an isolated config by test_status_helpers.py. Real commands are disabled.
import QtQuick
import Quickshell
import "main/modules" as Modules
import "main/services" as Services

Scope {
    id: root
    property int failures: 0
    property var calls: []
    property var counts: ({})

    function check(label, actual, expected) {
        const ok = JSON.stringify(actual) === JSON.stringify(expected);
        console.log((ok ? "PASS " : "FAIL ") + label + ": " + JSON.stringify(actual));
        if (!ok)
            failures++;
    }
    function count(name) {
        const next = Object.assign({}, counts);
        next[name] = (next[name] || 0) + 1;
        counts = next;
    }

    Services.ShellIpc { id: testIpc }
    Modules.Audio {
        id: audio
        ipc: testIpc
        moduleVisible: false
        interval: 0
        function refresh() { root.count("audio"); }
        function runCommand(command, detached = false) {
            root.calls = root.calls.concat([{command: command, detached: detached}]);
        }
    }
    Modules.Cpu {
        id: cpu
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        function refresh() { root.count("cpu"); }
    }
    Modules.Gpu {
        id: gpu
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        function refresh() { root.count("gpu"); }
    }
    Modules.Memory {
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        function refresh() { root.count("memory"); }
    }
    Modules.CodexUsage {
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        function refresh() { root.count("codex"); }
    }
    Modules.LlamaModels {
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        activeInterval: 0
        function refresh() { root.count("llama"); }
    }
    Modules.K8sAlerts {
        id: alerts
        ipc: testIpc
        barWindow: null
        interval: 0
        function refresh() { root.count("k8s"); }
    }
    Modules.Habits {
        id: habits
        ipc: testIpc
        barWindow: null
        interval: 0
        command: Quickshell.shellPath("fake_action.py")
        function refresh() { root.count("habits"); }
    }
    Modules.Updates {
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        function refresh() { root.count("updates"); }
    }
    Modules.SystemdFailedUnits {
        id: units
        ipc: testIpc
        barWindow: null
        interval: 0
        function refresh() { root.count("systemd"); }
    }
    Modules.FritzTraffic {
        ipc: testIpc
        barWindow: null
        moduleVisible: false
        interval: 0
        function refresh() { root.count("fritz"); }
    }
    Modules.Clock {
        id: clock
        ipc: testIpc
        barWindow: null
        // Do not instantiate the real calendar reader in an IPC routing test.
        function updateHover() {}
    }
    Modules.FritzTraffic {
        id: slowRouter
        barWindow: null
        interval: 100
        command: Quickshell.shellPath("fake_status.py")
    }

    Timer {
        interval: 250
        running: true
        onTriggered: {
            root.calls = [];
            audio.clicked(Qt.LeftButton);
            audio.clicked(Qt.RightButton);
            audio.clicked(Qt.MiddleButton);
            root.check("one audio action per click; GUI detached, mute tracked", root.calls, [
                {command: "pwvucontrol", detached: true},
                {command: "helvum", detached: true},
                {command: "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", detached: false}
            ]);
            root.check("guest CPU time counted once", cpu.statTotals([100, 0, 0, 900, 0, 0, 0, 0, 100, 0]).total, 1000);
            gpu.applyOutput("50, 100, 1000, 999.0, Test GPU\n__KERNEL_DRIVER__=999.0");
            gpu.applyOutput("[N/A], 100, 1000, 999.0, Test GPU\n__KERNEL_DRIVER__=999.0");
            root.check("unsupported GPU metrics report an error, not NaN", [gpu.hasError, gpu.utilization], [true, 50]);
            gpu.applyOutput("0, 0, 1000, 999.0, Test GPU\n__KERNEL_DRIVER__=999.0");
            root.check("GPU recovers on a valid reading", [gpu.hasError, gpu.utilization], [false, 0]);

            units.applyOutput(JSON.stringify({systemUnits: ["broken.service"], userUnits: [], error: ""}));
            units.applyOutput(JSON.stringify({systemUnits: null, userUnits: [], error: "Bus unavailable"}));
            root.check("failed systemd query preserves known units and error", [units.totalCount, units.errorText], [1, "Bus unavailable"]);
            units.applyOutput("{}");
            root.check("malformed systemd response is not treated as healthy", units.errorText.length > 0, true);
            units.applyOutput(JSON.stringify({systemUnits: [], userUnits: [], error: ""}));
            root.check("successful systemd query clears error", [units.totalCount, units.errorText], [0, ""]);

            root.counts = {};
            testIpc.refreshRequested("gpu");
            root.check("named refresh only reaches its module", root.counts, {gpu: 1});
            root.counts = {};
            testIpc.refreshRequested("all");
            for (const name of ["audio", "cpu", "gpu", "memory", "codex", "llama", "k8s", "habits", "updates", "systemd", "fritz"])
                root.check("refresh all: " + name, root.counts[name], 1);

            clock.popupPinned = false;
            testIpc.popupRequested("calendar");
            root.check("calendar popup IPC pins", clock.popupPinned, true);
            testIpc.popupRequested("calendar");
            root.check("calendar popup IPC unpins", clock.popupPinned, false);
            clock.popupIpcEnabled = false;
            testIpc.popupRequested("calendar");
            root.check("calendar IPC ignores an unfocused monitor", clock.popupPinned, false);
            clock.popupIpcEnabled = true;
            testIpc.popupRequested("habits");
            root.check("habits popup IPC pins", habits.popupPinned, true);
            testIpc.popupRequested("habits");
            root.check("habits popup IPC unpins", habits.popupPinned, false);
            alerts.applyOutput(JSON.stringify({state: "ok", watchdogRunning: true, counts: {total: 0}, alerts: []}));
            testIpc.popupRequested("k8s-alerts");
            root.check("healthy Kubernetes popup pins via IPC", [alerts.popupPinned, alerts.hasProblem], [true, false]);
            testIpc.popupRequested("k8s-alerts");
            root.check("healthy Kubernetes popup unpins via IPC", [alerts.popupPinned, alerts.hasProblem], [false, false]);

            habits.runAction(["first"], "habit:first");
            habits.runAction(["second"], "habit:second");
            habits.runAction(["first"], "habit:first");
            habits.runAction(["fail"], "habit:fail");
            habits.runAction(["after-failure"], "habit:after");
            root.check("mutations are queued, duplicate pending action ignored", [habits.pendingAction, habits.actionQueue.length, habits.isActionPending("habit:second")], ["habit:first", 3, true]);
        }
    }
    Timer {
        interval: 3500
        running: true
        onTriggered: {
            root.check("slow polls complete instead of being cancelled", [slowRouter.downMbit, slowRouter.errorText], [123, ""]);
            root.check("all habit actions finish and busy state clears", [habits.pendingAction, habits.actionQueue.length], ["", 0]);
            root.check("failed mutation remains visible after next action succeeds", habits.actionError, "Intentional action failure");
            console.log("HEADLESS_FAILURES=" + root.failures);
            Qt.quit();
        }
    }
}
