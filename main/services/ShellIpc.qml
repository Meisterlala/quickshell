import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal refreshRequested(string name)
    signal popupRequested(string name)

    property string lastMessage: "ready"

    IpcHandler {
        target: "bar"

        function refreshModule(name: string): void {
            root.lastMessage = `refresh:${name}`;
            root.refreshRequested(name);
        }

        function togglePopup(name: string): bool {
            if (!["calendar", "habits", "k8s-alerts", "notifications"].includes(name))
                return false;
            root.lastMessage = `popup:${name}`;
            root.popupRequested(name);
            return true;
        }

        function getState(): string {
            return root.lastMessage;
        }
    }
}
