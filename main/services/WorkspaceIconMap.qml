import QtQuick

QtObject {
    // Mirrors Waybar's window-rewrite style: class<regex>, title<regex>,
    // initialClass<regex>, and initialTitle<regex>. First match wins.
    readonly property var rules: [
        ["title", ".*youtube.*", ""],
        ["title", "OpenCode", ""],
        ["title", "OC \\|.*", ""],
        ["title", "π", "󰏿"],
        ["title", "nvim .*", ""],
        ["class", "zen", ""],
        ["class", "Alacritty", ""],
        ["class", "com.mitchellh.ghostty", ""],
        ["class", "Discord", ""],
        ["class", "Spotify", ""],
        ["class", "org.gnome.Nautilus", ""],
        ["class", "org.kde.dolphin", ""],
        ["class", "superProductivity", ""],
        ["class", "code", ""],
        ["class", "steam_app_.*", ""],
        ["class", "steam", ""],
        ["class", "fluffychat", ""],
        ["class", "Element", "󰘨"],
        ["class", "chromium", ""],
        ["class", "Slay the Spire 2", ""],
        ["class", "steam_app_1422450", ""],
        ["class", "Golf With Your Friends.x86_64", ""],
        ["class", "gamescope", ""],
        ["class", "mpv", ""],
        ["class", "steam_app_686060", ""],
        ["class", "org.mozilla.Thunderbird", ""],
        ["class", "xdg-desktop-portal-gtk", ""],
        ["class", "localsend", ""],
        ["class", "org.kde.keepsecret", ""],
        ["class", "com.gabm.satty", ""],
        ["class", "com.saivert.pwvucontrol", ""],
        ["class", "org.pipewire.Helvum", ""],
        ["class", "wev", ""],
        ["class", "ffxiv_dx11.exe", ""],
        ["class", "org.gnome.seahorse.Application", ""],
        ["class", "local.dailyplan.window", ""],
        ["class", "zenity", ""],
        ["class", "habits-desktop", ""],
        ["class", "google-chrome", ""],
        ["class", "org.kde.konsole", ""],
        ["class", "electron", ""],
        ["class", "org.coolercontrol.CoolerControl", "󰈐"],
        ["class", "habits", ""],
        ["class", "Emulator", ""],
        ["class", "jetbrains-studio", ""],
        ["class", "btrfs-assistant", ""],
        ["class", "scrcpy", ""],
        ["class", "com.misti.NvidiaDriverRestart", "󱄌"],
        ["class", "XIVLauncher.Core", ""],
        ["class", "GParted", "󰋊"],
        ["class", "org.gnome.eog", ""],
        ["class", "steam_app_3527290", ""],
        ["class", "dolphin", ""],
        ["class", "hyprland-share-picker", "󱒃"],
        ["class", "steam_app_4159377692", ""],
        ["class", "com.usebottles.bottles", "󰡔"],
        ["class", "steam_app_2929855285", ""],
        ["class", "heroic", ""],
        ["class", "steam_proton", ""],
        ["class", "steam_app_3713652275", ""],
        ["class", "mvdl", ""]
    ]

    function fieldValue(toplevel, field) {
        if (!toplevel)
            return "";

        if (field === "title")
            return toplevel.title || "";

        if (field === "class") {
            if (toplevel.lastIpcObject && toplevel.lastIpcObject.class)
                return toplevel.lastIpcObject.class;

            return toplevel.wayland ? toplevel.wayland.appId : "";
        }

        if (field === "initialClass")
            return toplevel.lastIpcObject && toplevel.lastIpcObject.initialClass ? toplevel.lastIpcObject.initialClass : "";

        if (field === "initialTitle")
            return toplevel.lastIpcObject && toplevel.lastIpcObject.initialTitle ? toplevel.lastIpcObject.initialTitle : "";

        return "";
    }

    function iconFor(toplevel) {
        for (const rule of rules) {
            if (new RegExp(rule[1], "i").test(fieldValue(toplevel, rule[0])))
                return rule[2];
        }

        return "";
    }
}
