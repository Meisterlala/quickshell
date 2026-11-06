//@ pragma UseQApplication

import "./services"
import Quickshell

Scope {
    id: root

    // One supervisor owns helper builds and their persistent status card.
    HelperBuildWindows {
        service: HelperBuild
    }

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
