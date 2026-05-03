import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dankFanStats"

    StyledText {
        width: parent.width
        text: "Dank Fan Stats"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows fan RPM plus CPU and GPU temperatures on the Dank bar from a root-managed JSON cache file."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "statsPath"
        label: "Stats File Path"
        description: "Path to the JSON file written by the privileged fan stats service."
        placeholder: "/run/dank-fan-stats/stats.json"
        defaultValue: "/run/dank-fan-stats/stats.json"
    }

    StringSetting {
        settingKey: "controlPath"
        label: "Control FIFO Path"
        description: "Writable FIFO used to send cooler boost toggle commands to the privileged daemon."
        placeholder: "/run/dank-fan-stats/control"
        defaultValue: "/run/dank-fan-stats/control"
    }

    StringSetting {
        settingKey: "updateInterval"
        label: "Refresh Interval (ms)"
        description: "How often the widget polls the JSON cache file. This does not change the systemd timer cadence."
        placeholder: "3000"
        defaultValue: "3000"
    }
}
