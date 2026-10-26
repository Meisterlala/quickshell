//@ pragma UseQApplication

import "./services"
import Quickshell

Scope {
    id: root

    ShellIpc {
        id: shellIpc
    }

    Notifications {
        id: notificationService
        ipc: shellIpc
    }

    NotificationWindows {
        service: notificationService
    }

    Bar {
        ipc: shellIpc
        notifications: notificationService
    }

}
