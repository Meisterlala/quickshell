import "./services"
import Quickshell

Scope {
    id: root

    ShellIpc {
        id: shellIpc
    }

    Bar {
        ipc: shellIpc
    }

}
