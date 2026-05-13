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

    function togglePopup(name: string): void {
      root.lastMessage = `popup:${name}`;
      root.popupRequested(name);
    }

    function getState(): string {
      return root.lastMessage;
    }
  }
}
