import QtQuick
import Quickshell
import Quickshell.Io

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var pluginService: null
    property string pluginId: "dankFanStats"
    property string statsPath: "/run/dank-fan-stats/stats.json"
    property string controlPath: "/run/dank-fan-stats/control"
    property int updateInterval: 3000

    property color boostColor: "#FF9800"

    property int fanRpm: 0
    property bool coolerBoostEnabled: false
    property bool statsAvailable: false
    property string statusText: "Polling fan stats"
    property string errorText: ""

    Component.onCompleted: {
        if (pluginService) {
            statsPath = pluginService.loadPluginData(pluginId, "statsPath", statsPath);
            controlPath = pluginService.loadPluginData(pluginId, "controlPath", controlPath);
            updateInterval = parseInt(pluginService.loadPluginData(pluginId, "updateInterval", updateInterval)) || 3000;
        }
    }

    function statColor() {
        return root.coolerBoostEnabled ? root.boostColor : Theme.surfaceText;
    }

    function setError(message) {
        if (!message || message.trim().length === 0)
            message = "No stats file content yet";
        root.statsAvailable = false;
        root.errorText = message.trim();
        root.statusText = "Sensor read failed";
    }

    function parseOutput(output) {
        const cleaned = output.trim();

        if (cleaned.length === 0) {
            root.setError("");
            return;
        }

        let data = null;
        try {
            data = JSON.parse(cleaned);
        } catch (e) {
            root.setError("Stats JSON parse failed");
            return;
        }

        if (!data.ok) {
            root.setError(data.error || "Stats service reported an error");
            return;
        }

        root.fanRpm = parseInt(data.fanRpm) || 0;
        root.coolerBoostEnabled = (data.coolerBoost || "").toString().toLowerCase() === "on";
        root.statsAvailable = true;
        root.errorText = "";
        root.statusText = root.fanRpm > 0
            ? `${root.fanRpm} RPM • Cooler Boost ${root.coolerBoostEnabled ? "On" : "Off"}`
            : `Fan stopped • Cooler Boost ${root.coolerBoostEnabled ? "On" : "Off"}`;
    }

    function toggleCoolerBoost() {
        Quickshell.execDetached(["sh", "-c", "printf 'toggle\\n' > \"" + root.controlPath + "\""]);
    }

    Timer {
        id: pollTimer
        interval: root.updateInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pollProcess.running)
                pollProcess.running = true;
        }
    }

    Process {
        id: pollProcess
        command: ["cat", root.statsPath]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseOutput(text)
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight

            width: implicitWidth
            height: implicitHeight

            Row {
                id: pillRow
                spacing: Theme.spacingXS
                anchors.centerIn: parent

                anchors.margins: Theme.spacingS

                DankIcon {
                    name: "mode_fan"
                    size: Theme.fontSizeSmall
                    color: root.statsAvailable ? root.statColor() : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.statsAvailable ? `${root.fanRpm}` : "--"
                    color: root.statsAvailable ? Theme.surfaceText : Theme.surfaceVariantText

                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium

                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleCoolerBoost()
            }
        }
    }
}
