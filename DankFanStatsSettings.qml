import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dankFanStats"

    StyledText {
        width: parent.width
        text: I18n.trFor("dankFanStats", "Dank Fan Stats")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("dankFanStats", "Fan RPM and temperatures in the bar, with a tabbed MSI EC control panel for performance modes, battery care, the advanced fan curve and the keyboard backlight.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("dankFanStats", "Bar pill")
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.primary
    }

    SelectionSetting {
        settingKey: "pillMode"
        label: I18n.trFor("dankFanStats", "Pill content")
        description: I18n.trFor("dankFanStats", "Choose what the bar pill shows alongside the fan icon.")
        options: [
            {
                "label": I18n.trFor("dankFanStats", "Fan RPM"),
                "value": "rpm"
            },
            {
                "label": I18n.trFor("dankFanStats", "CPU temperature"),
                "value": "cpu"
            },
            {
                "label": I18n.trFor("dankFanStats", "GPU temperature"),
                "value": "gpu"
            },
            {
                "label": I18n.trFor("dankFanStats", "CPU temperature and fan"),
                "value": "cpuRpm"
            }
        ]
        defaultValue: "rpm"
    }

    ToggleSetting {
        settingKey: "showPillIcon"
        label: I18n.trFor("dankFanStats", "Show fan icon")
        description: I18n.trFor("dankFanStats", "Draw the fan icon before the pill value.")
        defaultValue: true
    }

    SliderSetting {
        settingKey: "updateInterval"
        label: I18n.trFor("dankFanStats", "Refresh interval")
        description: I18n.trFor("dankFanStats", "How often the widget reads the stats cache.")
        defaultValue: 3000
        minimum: 1000
        maximum: 10000
        startIcon: "speed"
        unit: " ms"
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("dankFanStats", "Service")
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.primary
    }

    StringSetting {
        settingKey: "statsPath"
        label: I18n.trFor("dankFanStats", "Stats file path")
        description: I18n.trFor("dankFanStats", "JSON cache written by the privileged fan service.")
        placeholder: "/run/dank-fan-stats/stats.json"
        defaultValue: "/run/dank-fan-stats/stats.json"
    }

    StringSetting {
        settingKey: "controlPath"
        label: I18n.trFor("dankFanStats", "Control FIFO path")
        description: I18n.trFor("dankFanStats", "Writable FIFO used to send commands to the privileged daemon.")
        placeholder: "/run/dank-fan-stats/control"
        defaultValue: "/run/dank-fan-stats/control"
    }
}
