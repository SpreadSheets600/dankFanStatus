import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "dank-fan-stats"

    property string statsPath: pluginData.statsPath || "/run/dank-fan-stats/stats.json"
    property string controlPath: pluginData.controlPath || "/run/dank-fan-stats/control"
    readonly property int updateInterval: {
        const parsed = parseInt(pluginData.updateInterval);
        if (isNaN(parsed))
            return 3000;
        return Math.max(1000, Math.min(10000, parsed));
    }
    readonly property string pillMode: pluginData.pillMode || "rpm"
    readonly property bool showPillIcon: pluginData.showPillIcon !== false

    property bool statsAvailable: false
    property string errorText: ""
    property int fanRpm: 0
    property int cpuTemp: 0
    property int gpuTemp: 0
    property int cpuFan: 0
    property int gpuFan: 0
    property string fwVersion: ""

    property string coolerBoost: "off"
    property string superBattery: "off"
    property string webcam: "on"
    property string webcamBlock: "off"
    property string shiftMode: ""
    property var shiftModes: []
    property string fanMode: ""
    property var fanModes: []
    property string fnKey: "left"
    property string winKey: "right"
    property int chargeStart: 0
    property int chargeEnd: 100
    property int kbdBacklight: 0
    property int kbdBacklightMax: 0

    property bool coolerBoostSupported: true
    property bool superBatterySupported: true
    property bool webcamSupported: true
    property bool webcamBlockSupported: true
    property bool fnKeySupported: true
    property bool winKeySupported: true
    property bool advancedSupported: true
    property bool curveWritable: true
    property bool chargeSupported: true
    property bool kbdBacklightSupported: true

    property int tabIndex: 0
    property var curveCpuTemps: [50, 60, 65, 70, 75, 80]
    property var curveCpuSpeeds: [0, 40, 50, 60, 70, 80, 85]
    property var curveGpuTemps: [50, 60, 65, 70, 75, 80]
    property var curveGpuSpeeds: [0, 40, 50, 60, 70, 80, 85]
    property int curveTarget: 0
    property bool curveDirty: false

    readonly property bool advancedOn: root.fanMode === "advanced"
    readonly property bool boostOn: root.coolerBoost === "on"
    readonly property bool curveReady: root.advancedSupported && root.curveWritable
    readonly property bool functionKeysSupported: root.fnKeySupported || root.winKeySupported
    readonly property var kbdLabels: {
        const maximum = root.kbdBacklightMax;
        if (maximum <= 0)
            return [];
        if (maximum === 3)
            return [I18n.trFor("dankFanStats", "Off"), I18n.trFor("dankFanStats", "Low"), I18n.trFor("dankFanStats", "Medium"), I18n.trFor("dankFanStats", "High")];
        const labels = [I18n.trFor("dankFanStats", "Off")];
        for (let value = 1; value <= maximum; value++)
            labels.push(String(value));
        return labels;
    }
    readonly property var curveTemps: root.curveTarget === 0 ? root.curveCpuTemps : root.curveGpuTemps
    readonly property var curveSpeeds: root.curveTarget === 0 ? root.curveCpuSpeeds : root.curveGpuSpeeds

    readonly property var telemetry: [
        {
            "label": I18n.trFor("dankFanStats", "CPU"),
            "value": root.tempText(root.cpuTemp),
            "sub": root.fanPercentText(root.cpuFan),
            "icon": "memory",
            "accent": Theme.primary,
            "valueColor": root.tempColor(root.cpuTemp)
        },
        {
            "label": I18n.trFor("dankFanStats", "GPU"),
            "value": root.tempText(root.gpuTemp),
            "sub": root.fanPercentText(root.gpuFan),
            "icon": "developer_board",
            "accent": Theme.tertiary,
            "valueColor": root.tempColor(root.gpuTemp)
        },
        {
            "label": I18n.trFor("dankFanStats", "FAN"),
            "value": root.rpmText(root.fanRpm),
            "sub": I18n.trFor("dankFanStats", "RPM"),
            "icon": "mode_fan",
            "accent": Theme.secondary,
            "valueColor": Theme.surfaceText
        }
    ]

    readonly property var toggleItems: {
        const items = [];
        if (root.coolerBoostSupported)
            items.push({
                "key": "cooler_boost",
                "label": I18n.trFor("dankFanStats", "Cooler Boost"),
                "description": I18n.trFor("dankFanStats", "Fans at maximum speed")
            });
        if (root.superBatterySupported)
            items.push({
                "key": "super_battery",
                "label": I18n.trFor("dankFanStats", "Super Battery"),
                "description": I18n.trFor("dankFanStats", "Reduce power draw")
            });
        if (root.webcamSupported)
            items.push({
                "key": "webcam",
                "label": I18n.trFor("dankFanStats", "Camera"),
                "description": I18n.trFor("dankFanStats", "Enable or disable the webcam")
            });
        if (root.webcamBlockSupported)
            items.push({
                "key": "webcam_block",
                "label": I18n.trFor("dankFanStats", "Block Camera"),
                "description": I18n.trFor("dankFanStats", "Hardware camera privacy switch")
            });
        return items;
    }

    readonly property string pillText: {
        if (!root.statsAvailable)
            return "--";
        switch (root.pillMode) {
        case "cpu":
            return root.tempShort(root.cpuTemp);
        case "gpu":
            return root.tempShort(root.gpuTemp);
        case "cpuRpm":
            return root.tempShort(root.cpuTemp) + " " + root.rpmText(root.fanRpm);
        default:
            return root.rpmText(root.fanRpm);
        }
    }

    readonly property color pillTextColor: {
        if (!root.statsAvailable)
            return Theme.surfaceVariantText;
        if (root.boostOn)
            return Theme.warning;
        if (root.pillMode === "cpu" || root.pillMode === "cpuRpm") {
            if (root.cpuTemp >= 90)
                return Theme.tempDanger;
            if (root.cpuTemp >= 75)
                return Theme.tempWarning;
        }
        if (root.pillMode === "gpu") {
            if (root.gpuTemp >= 90)
                return Theme.tempDanger;
            if (root.gpuTemp >= 75)
                return Theme.tempWarning;
        }
        return Theme.widgetTextColor;
    }

    readonly property color pillIconColor: {
        if (!root.statsAvailable)
            return Theme.widgetInactiveIconColor;
        if (root.boostOn)
            return Theme.warning;
        return Theme.widgetIconColor;
    }

    component SectionTitle: StyledText {
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.primary
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.outlineVariant
        opacity: 0.55
    }

    component InfoRow: Item {
        property string label: ""
        property string value: ""
        property color valueColor: Theme.surfaceText

        width: parent ? parent.width : 0
        height: Math.max(24, labelText.implicitHeight, valueText.implicitHeight)

        StyledText {
            id: labelText
            anchors.left: parent.left
            anchors.right: valueText.left
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            elide: Text.ElideRight
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }

        StyledText {
            id: valueText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: parent.valueColor
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
        }
    }

    function intValue(value, fallback) {
        const parsed = parseInt(value);
        return isNaN(parsed) ? fallback : parsed;
    }

    function tempText(value) {
        return root.statsAvailable && value > 0 ? value + "°C" : "--";
    }

    function tempShort(value) {
        return root.statsAvailable && value > 0 ? value + "°" : "--";
    }

    function fanPercentText(value) {
        return root.statsAvailable && value > 0 ? value + "% " + I18n.trFor("dankFanStats", "fan") : I18n.trFor("dankFanStats", "fan --");
    }

    function rpmText(value) {
        if (!root.statsAvailable)
            return "--";
        const rpm = Math.max(0, root.intValue(value, 0));
        if (rpm <= 0)
            return "0";
        if (rpm >= 1000)
            return (rpm / 1000).toFixed(1) + "k";
        return String(rpm);
    }

    function tempColor(value) {
        if (!root.statsAvailable || value <= 0)
            return Theme.surfaceVariantText;
        if (value >= 90)
            return Theme.tempDanger;
        if (value >= 75)
            return Theme.tempWarning;
        return Theme.surfaceText;
    }

    function toggleState(key) {
        switch (key) {
        case "cooler_boost":
            return root.coolerBoost === "on";
        case "super_battery":
            return root.superBattery === "on";
        case "webcam":
            return root.webcam === "on";
        case "webcam_block":
            return root.webcamBlock === "on";
        }
        return false;
    }

    function validCurve(temps, speeds) {
        if (!Array.isArray(temps) || !Array.isArray(speeds))
            return false;
        if (temps.length !== 6 || speeds.length !== 7)
            return false;
        for (let index = 0; index < temps.length; index++) {
            const temp = Number(temps[index]);
            if (!(temp > 0 && temp <= 100))
                return false;
            if (index > 0 && temp <= Number(temps[index - 1]))
                return false;
        }
        for (let index = 0; index < speeds.length; index++) {
            const speed = Number(speeds[index]);
            if (!(speed >= 0 && speed <= 100))
                return false;
            if (index > 0 && speed < Number(speeds[index - 1]))
                return false;
        }
        return true;
    }

    function parseOutput(output) {
        const cleaned = output.trim();

        if (cleaned.length === 0) {
            root.statsAvailable = false;
            root.errorText = I18n.trFor("dankFanStats", "No stats file content yet");
            return;
        }

        let data = null;
        try {
            data = JSON.parse(cleaned);
        } catch (error) {
            root.statsAvailable = false;
            root.errorText = I18n.trFor("dankFanStats", "Could not parse the stats JSON");
            return;
        }

        if (!data || typeof data !== "object") {
            root.statsAvailable = false;
            root.errorText = I18n.trFor("dankFanStats", "The stats file is empty");
            return;
        }

        root.statsAvailable = data.ok === true;
        root.errorText = data.ok === true ? "" : (data.error || I18n.trFor("dankFanStats", "The fan service reported an error"));

        root.fanRpm = root.intValue(data.fanRpm, 0);
        root.cpuTemp = root.intValue(data.cpuTemp, 0);
        root.gpuTemp = root.intValue(data.gpuTemp, 0);
        root.cpuFan = root.intValue(data.cpuFan, 0);
        root.gpuFan = root.intValue(data.gpuFan, 0);
        root.fwVersion = data.fwVersion || "";

        root.coolerBoost = (data.coolerBoost || "off").toString().toLowerCase();
        root.superBattery = (data.superBattery || "off").toString().toLowerCase();
        root.webcam = (data.webcam || "").toString().toLowerCase();
        root.webcamBlock = (data.webcamBlock || "").toString().toLowerCase();
        root.shiftModes = Array.isArray(data.shiftModes) ? data.shiftModes : [];
        root.fanModes = Array.isArray(data.fanModes) ? data.fanModes : [];
        if (data.shiftMode !== undefined)
            root.shiftMode = (data.shiftMode || "").toString();
        if (data.fanMode !== undefined)
            root.fanMode = (data.fanMode || "").toString();
        root.fnKey = (data.fnKey || "").toString().toLowerCase();
        root.winKey = (data.winKey || "").toString().toLowerCase();
        root.chargeStart = root.intValue(data.chargeStart, 0);
        root.chargeEnd = root.intValue(data.chargeEnd, 100);
        root.kbdBacklight = root.intValue(data.kbdBacklight, 0);
        root.kbdBacklightMax = root.intValue(data.kbdBacklightMax, 0);

        if (data.advancedSupported !== undefined)
            root.advancedSupported = data.advancedSupported === true;
        if (data.curveWritable !== undefined)
            root.curveWritable = data.curveWritable === true;
        if (data.coolerBoostSupported !== undefined)
            root.coolerBoostSupported = data.coolerBoostSupported === true;
        if (data.superBatterySupported !== undefined)
            root.superBatterySupported = data.superBatterySupported === true;
        if (data.webcamSupported !== undefined)
            root.webcamSupported = data.webcamSupported === true;
        if (data.webcamBlockSupported !== undefined)
            root.webcamBlockSupported = data.webcamBlockSupported === true;
        if (data.fnKeySupported !== undefined)
            root.fnKeySupported = data.fnKeySupported === true;
        if (data.winKeySupported !== undefined)
            root.winKeySupported = data.winKeySupported === true;
        if (data.chargeSupported !== undefined)
            root.chargeSupported = data.chargeSupported === true;
        if (data.kbdBacklightSupported !== undefined)
            root.kbdBacklightSupported = data.kbdBacklightSupported === true;

        const curve = data.curve;
        if (data.ok === true && curve && !root.curveDirty) {
            if (root.validCurve(curve.cpuTemps, curve.cpuSpeeds)) {
                root.curveCpuTemps = curve.cpuTemps.map(Number);
                root.curveCpuSpeeds = curve.cpuSpeeds.map(Number);
            }
            if (root.validCurve(curve.gpuTemps, curve.gpuSpeeds)) {
                root.curveGpuTemps = curve.gpuTemps.map(Number);
                root.curveGpuSpeeds = curve.gpuSpeeds.map(Number);
            }
        }
    }

    function sendCommand(command) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", command, root.controlPath]);
        pollSoon.restart();
    }

    function refreshNow() {
        root.sendCommand("refresh");
    }

    function poll() {
        if (!pollProcess.running)
            pollProcess.running = true;
    }

    function setMode(kind, value) {
        if (!value)
            return;
        if (kind === "fan_mode" && value === "advanced") {
            if (root.curveReady) {
                root.applyCurve();
            } else {
                root.sendCommand("set fan_mode advanced");
                root.fanMode = "advanced";
            }
            return;
        }
        if (kind === "shift_mode")
            root.shiftMode = value;
        else if (kind === "fan_mode")
            root.fanMode = value;
        root.sendCommand("set " + kind + " " + value);
    }

    function setToggle(key, enabled) {
        const value = enabled ? "on" : "off";
        switch (key) {
        case "cooler_boost":
            root.coolerBoost = value;
            break;
        case "super_battery":
            root.superBattery = value;
            break;
        case "webcam":
            root.webcam = value;
            break;
        case "webcam_block":
            root.webcamBlock = value;
            break;
        }
        root.sendCommand("set " + key + " " + value);
    }

    function setKeySwap(swapped) {
        const fn = swapped ? "right" : "left";
        const win = swapped ? "left" : "right";
        if (root.fnKey === fn && root.winKey === win)
            return;
        root.fnKey = fn;
        root.winKey = win;
        root.sendCommand("set fn_key " + fn + "\nset win_key " + win);
    }

    function setKbdBacklight(value) {
        if (!root.kbdBacklightSupported || value === root.kbdBacklight)
            return;
        root.kbdBacklight = value;
        root.sendCommand("set kbd_backlight " + value);
    }

    function setCharge(key, value) {
        if (!root.chargeSupported)
            return;
        let next = Math.max(0, Math.min(100, value));
        if (key === "charge_start") {
            next = Math.max(0, Math.min(next, root.chargeEnd - 1));
            root.chargeStart = next;
        } else {
            next = Math.min(100, Math.max(next, root.chargeStart + 1));
            root.chargeEnd = next;
        }
        root.sendCommand("set " + key + " " + next);
    }

    function curveCommand() {
        return "set fan_curve " + root.curveCpuTemps.join(",") + " " + root.curveCpuSpeeds.join(",") + " " + root.curveGpuTemps.join(",") + " " + root.curveGpuSpeeds.join(",");
    }

    function applyCurve() {
        if (!root.curveReady)
            return;
        root.sendCommand(root.curveCommand() + "\nset advanced on");
        root.fanMode = "advanced";
        root.curveDirty = false;
    }

    function setAdvanced(enabled) {
        if (enabled) {
            root.applyCurve();
            return;
        }
        if (!root.advancedOn)
            return;
        root.sendCommand("set advanced off");
        root.fanMode = "auto";
    }

    function setCurve(temps, speeds) {
        if (root.curveTarget === 0) {
            root.curveCpuTemps = temps.slice();
            root.curveCpuSpeeds = speeds.slice();
        } else {
            root.curveGpuTemps = temps.slice();
            root.curveGpuSpeeds = speeds.slice();
        }
        root.curveDirty = true;
    }

    function applyPreset(name) {
        let temps;
        let speeds;
        if (name === "silent") {
            temps = [60, 65, 70, 75, 80, 85];
            speeds = [0, 25, 35, 45, 55, 65, 75];
        } else if (name === "performance") {
            temps = [45, 50, 55, 60, 65, 70];
            speeds = [30, 45, 60, 75, 85, 95, 100];
        } else {
            temps = [50, 60, 65, 70, 75, 80];
            speeds = [0, 40, 50, 60, 70, 80, 85];
        }
        root.curveCpuTemps = temps.slice();
        root.curveCpuSpeeds = speeds.slice();
        root.curveGpuTemps = temps.slice();
        root.curveGpuSpeeds = speeds.slice();
        root.curveDirty = true;
    }

    function resetCurve() {
        root.curveCpuTemps = [50, 60, 65, 70, 75, 80];
        root.curveCpuSpeeds = [0, 40, 50, 60, 70, 80, 85];
        root.curveGpuTemps = [50, 60, 65, 70, 75, 80];
        root.curveGpuSpeeds = [0, 40, 50, 60, 70, 80, 85];
        root.curveDirty = true;
    }

    Timer {
        id: pollTimer
        interval: root.updateInterval
        running: root.surfaceLive || root.interactionActive
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    Timer {
        id: pollSoon
        interval: 220
        repeat: false
        onTriggered: root.poll()
    }

    Process {
        id: pollProcess
        command: ["cat", root.statsPath]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseOutput(text)
        }
    }

    pillRightClickAction: () => root.coolerBoostSupported ? root.setToggle("cooler_boost", !root.boostOn) : root.refreshNow()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

            DIcon {
                name: "mode_fan"
                visible: root.showPillIcon
                size: root.iconSize
                color: root.pillIconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pillText
                color: root.pillTextColor
                font.pixelSize: root.textSize
                font.weight: Theme.fontWeightMedium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS
            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

            DIcon {
                name: "mode_fan"
                visible: root.showPillIcon
                size: root.iconSize
                color: root.pillIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.pillText
                color: root.pillTextColor
                font.pixelSize: root.textSize
                font.weight: Theme.fontWeightMedium
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 420

    popoutContent: Component {
        PopoutComponent {
            id: menu

            width: parent ? parent.width : 0
            headerText: I18n.trFor("dankFanStats", "Fan Control")
            detailsText: root.statsAvailable ? (root.shiftMode ? root.shiftMode + (root.fwVersion.length > 0 ? "  ·  " + root.fwVersion : "") : (root.fwVersion || I18n.trFor("dankFanStats", "MSI EC controller"))) : (root.errorText || I18n.trFor("dankFanStats", "Waiting for the fan daemon..."))

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    DActionButton {
                        visible: root.coolerBoostSupported
                        iconName: "ac_unit"
                        iconColor: root.boostOn ? Theme.primary : Theme.surfaceVariantText
                        iconFilled: root.boostOn
                        tooltipText: I18n.trFor("dankFanStats", "Toggle Cooler Boost")
                        onClicked: root.setToggle("cooler_boost", !root.boostOn)
                    }

                    DActionButton {
                        iconName: "refresh"
                        tooltipText: I18n.trFor("dankFanStats", "Refresh")
                        onClicked: root.refreshNow()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                DTabBar {
                    id: tabBar

                    width: parent.width
                    tabHeight: 44
                    currentIndex: root.tabIndex
                    model: [
                        {
                            "text": I18n.trFor("dankFanStats", "Stats"),
                            "icon": "thermostat"
                        },
                        {
                            "text": I18n.trFor("dankFanStats", "Settings"),
                            "icon": "tune"
                        },
                        {
                            "text": I18n.trFor("dankFanStats", "Curve"),
                            "icon": "show_chart"
                        },
                        {
                            "text": I18n.trFor("dankFanStats", "Keyboard"),
                            "icon": "keyboard"
                        }
                    ]
                    onTabClicked: index => {
                        root.tabIndex = index;
                        if (index === 2)
                            curveCanvas.requestPaint();
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 0

                    Row {
                        width: parent.width
                        spacing: Theme.groupedListGap

                        Repeater {
                            model: root.telemetry

                            DCard {
                                required property var modelData
                                required property int index

                                width: (parent.width - parent.spacing * Math.max(0, root.telemetry.length - 1)) / root.telemetry.length
                                height: Math.max(112, telemetryCardColumn.implicitHeight + Theme.spacingM * 2)

                                Column {
                                    id: telemetryCardColumn

                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    Row {
                                        spacing: Theme.spacingS

                                        StyledRect {
                                            width: 28
                                            height: 28
                                            radius: Theme.cornerRadiusS
                                            color: Theme.withAlpha(modelData.accent, 0.14)

                                            DIcon {
                                                anchors.centerIn: parent
                                                name: modelData.icon
                                                size: Theme.iconSizeSmall
                                                color: modelData.accent
                                            }
                                        }

                                        StyledText {
                                            text: modelData.label
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Theme.fontWeightMedium
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: modelData.value
                                        color: modelData.valueColor
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeXXLarge
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        text: modelData.sub
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }
                            }
                        }
                    }

                    DCard {
                        width: parent.width
                        height: quickColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.coolerBoostSupported

                        Column {
                            id: quickColumn
                            width: parent.width
                            spacing: Theme.spacingXXS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Quick control")
                            }

                            DToggle {
                                width: parent.width
                                text: I18n.trFor("dankFanStats", "Cooler Boost")
                                description: root.boostOn ? I18n.trFor("dankFanStats", "Fans at maximum speed") : I18n.trFor("dankFanStats", "Automatic fan curve")
                                checked: root.boostOn
                                onToggled: checked => root.setToggle("cooler_boost", checked)
                            }
                        }
                    }

                    DCard {
                        width: parent.width
                        height: systemColumn.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: systemColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "System")
                            }

                            InfoRow {
                                label: I18n.trFor("dankFanStats", "Performance mode")
                                value: root.shiftMode || "-"
                            }

                            Divider {}

                            InfoRow {
                                label: I18n.trFor("dankFanStats", "Fan mode")
                                value: root.fanMode || "-"
                            }

                            Divider {}

                            InfoRow {
                                label: I18n.trFor("dankFanStats", "Firmware")
                                value: root.fwVersion || "-"
                            }

                            Divider {}

                            InfoRow {
                                label: I18n.trFor("dankFanStats", "Daemon")
                                value: root.statsAvailable ? I18n.trFor("dankFanStats", "Online") : I18n.trFor("dankFanStats", "Offline")
                                valueColor: root.statsAvailable ? Theme.success : Theme.error
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 1

                    DCard {
                        width: parent.width
                        height: performanceColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.shiftModes.length > 0 || root.fanModes.length > 0

                        Column {
                            id: performanceColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Performance")
                            }

                            Column {
                                width: parent.width
                                spacing: Theme.spacingXS
                                visible: root.shiftModes.length > 0

                                StyledText {
                                    text: I18n.trFor("dankFanStats", "Performance mode")
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                }

                                DButtonGroup {
                                    width: parent.width
                                    fillWidth: true
                                    size: "small"
                                    checkEnabled: false
                                    maximumWidth: parent.width
                                    model: root.shiftModes
                                    currentIndex: root.shiftModes.indexOf(root.shiftMode)
                                    onSelectionChanged: (index, selected) => {
                                        if (selected)
                                            root.setMode("shift_mode", root.shiftModes[index]);
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: Theme.spacingXS
                                visible: root.fanModes.length > 0

                                StyledText {
                                    text: I18n.trFor("dankFanStats", "Fan mode")
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                }

                                DButtonGroup {
                                    width: parent.width
                                    fillWidth: true
                                    size: "small"
                                    checkEnabled: false
                                    maximumWidth: parent.width
                                    model: root.fanModes
                                    currentIndex: root.fanModes.indexOf(root.fanMode)
                                    onSelectionChanged: (index, selected) => {
                                        if (selected)
                                            root.setMode("fan_mode", root.fanModes[index]);
                                    }
                                }
                            }
                        }
                    }

                    DCard {
                        width: parent.width
                        height: featuresColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.toggleItems.length > 0

                        Column {
                            id: featuresColumn
                            width: parent.width
                            spacing: Theme.spacingXS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Features")
                            }

                            Repeater {
                                model: root.toggleItems

                                Column {
                                    required property var modelData
                                    required property int index

                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    DToggle {
                                        width: parent.width
                                        text: modelData.label
                                        description: modelData.description
                                        checked: root.toggleState(modelData.key)
                                        onToggled: checked => root.setToggle(modelData.key, checked)
                                    }

                                    Divider {
                                        visible: index < root.toggleItems.length - 1
                                    }
                                }
                            }
                        }
                    }

                    DCard {
                        width: parent.width
                        height: batteryColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.chargeSupported

                        Column {
                            id: batteryColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            Item {
                                width: parent.width
                                height: Math.max(chargeTitle.implicitHeight, chargeValue.implicitHeight)

                                SectionTitle {
                                    id: chargeTitle
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.trFor("dankFanStats", "Battery care")
                                }

                                StyledText {
                                    id: chargeValue
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.chargeStart + "% - " + root.chargeEnd + "%"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            DSlider {
                                id: chargeStartSlider
                                width: parent.width
                                size: "s"
                                minimum: 0
                                maximum: 100
                                step: 1
                                unit: "%"
                                startIcon: "battery_charging_full"
                                onSliderDragFinished: finalValue => root.setCharge("charge_start", finalValue)

                                Binding on value {
                                    value: root.chargeStart
                                    when: !chargeStartSlider.isDragging
                                }
                            }

                            DSlider {
                                id: chargeEndSlider
                                width: parent.width
                                size: "s"
                                minimum: 0
                                maximum: 100
                                step: 1
                                unit: "%"
                                endIcon: "battery_full"
                                onSliderDragFinished: finalValue => root.setCharge("charge_end", finalValue)

                                Binding on value {
                                    value: root.chargeEnd
                                    when: !chargeEndSlider.isDragging
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: I18n.trFor("dankFanStats", "Charging starts below the first threshold and stops at the second.")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 2

                    DCard {
                        width: parent.width
                        height: curveCardColumn.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: curveCardColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            Item {
                                width: parent.width
                                height: Math.max(curveTitle.implicitHeight, curveReadout.implicitHeight)

                                SectionTitle {
                                    id: curveTitle
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.trFor("dankFanStats", "Fan curve")
                                }

                                StyledText {
                                    id: curveReadout
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: graph.focusHandle >= 0 ? graph.pointText(graph.focusHandle) : (root.curveDirty ? I18n.trFor("dankFanStats", "Unsaved changes") : (root.advancedOn ? I18n.trFor("dankFanStats", "Active") : I18n.trFor("dankFanStats", "Inactive")))
                                    color: root.curveDirty ? Theme.warning : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            DToggle {
                                width: parent.width
                                text: I18n.trFor("dankFanStats", "Advanced fan control")
                                description: !root.advancedSupported ? I18n.trFor("dankFanStats", "The driver does not expose an advanced fan mode") : (!root.curveWritable ? I18n.trFor("dankFanStats", "Raw EC writes are not enabled") : (root.advancedOn ? I18n.trFor("dankFanStats", "The EC is following this curve") : I18n.trFor("dankFanStats", "The EC uses its automatic curve")))
                                checked: root.advancedOn
                                enabled: root.curveReady || root.advancedOn
                                onToggled: checked => root.setAdvanced(checked)
                            }

                            Item {
                                id: graph

                                readonly property real padLeft: 32
                                readonly property real padRight: 10
                                readonly property real padTop: 10
                                readonly property real padBottom: 22
                                readonly property real plotW: Math.max(1, width - padLeft - padRight)
                                readonly property real plotH: Math.max(1, height - padTop - padBottom)
                                readonly property real tempMin: 30
                                readonly property real tempMax: 100
                                readonly property real tempStep: 10

                                property int activeHandle: -1
                                property int hoverHandle: -1
                                readonly property int focusHandle: activeHandle >= 0 ? activeHandle : hoverHandle

                                width: parent.width
                                height: 210
                                opacity: root.curveReady ? 1 : 0.55

                                function xFor(temp) {
                                    return padLeft + (temp - tempMin) / (tempMax - tempMin) * plotW;
                                }

                                function yFor(percent) {
                                    return padTop + (1 - percent / 100) * plotH;
                                }

                                function tempFor(x) {
                                    return tempMin + (x - padLeft) / plotW * (tempMax - tempMin);
                                }

                                function percentFor(y) {
                                    return (1 - (y - padTop) / plotH) * 100;
                                }

                                function handlePos(temps, speeds, index) {
                                    return index === 0 ? Qt.point(xFor(tempMin), yFor(speeds[0])) : Qt.point(xFor(temps[index - 1]), yFor(speeds[index]));
                                }

                                function rgba(color, alpha) {
                                    return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + "," + Math.round(color.b * 255) + "," + alpha + ")";
                                }

                                function pointText(index) {
                                    const temp = index > 0 ? root.curveTemps[index - 1] : tempMin;
                                    return temp + "°C  " + root.curveSpeeds[index] + "%";
                                }

                                function tracePath(ctx, temps, speeds) {
                                    ctx.moveTo(xFor(tempMin), yFor(speeds[0]));
                                    for (let index = 1; index <= 6; index++) {
                                        const x = xFor(temps[index - 1]);
                                        ctx.lineTo(x, yFor(speeds[index - 1]));
                                        ctx.lineTo(x, yFor(speeds[index]));
                                    }
                                    ctx.lineTo(xFor(tempMax), yFor(speeds[6]));
                                }

                                function fillCurve(ctx, temps, speeds, color, alpha) {
                                    const gradient = ctx.createLinearGradient(0, padTop, 0, padTop + plotH);
                                    gradient.addColorStop(0, rgba(color, alpha));
                                    gradient.addColorStop(1, rgba(color, 0.02));
                                    ctx.beginPath();
                                    tracePath(ctx, temps, speeds);
                                    ctx.lineTo(xFor(tempMax), padTop + plotH);
                                    ctx.lineTo(xFor(tempMin), padTop + plotH);
                                    ctx.closePath();
                                    ctx.fillStyle = gradient;
                                    ctx.fill();
                                }

                                function strokeCurve(ctx, temps, speeds, alpha, color, handles, lineWidth) {
                                    ctx.beginPath();
                                    tracePath(ctx, temps, speeds);
                                    ctx.lineWidth = lineWidth;
                                    ctx.lineJoin = "round";
                                    ctx.strokeStyle = rgba(color, alpha);
                                    ctx.stroke();

                                    if (!handles)
                                        return;

                                    ctx.fillStyle = rgba(color, 1);
                                    for (let index = 0; index <= 6; index++) {
                                        const point = handlePos(temps, speeds, index);
                                        ctx.beginPath();
                                        ctx.arc(point.x, point.y, 4.5, 0, Math.PI * 2);
                                        ctx.fill();
                                    }

                                    if (focusHandle < 0)
                                        return;

                                    const focus = handlePos(temps, speeds, focusHandle);
                                    ctx.beginPath();
                                    ctx.arc(focus.x, focus.y, 8, 0, Math.PI * 2);
                                    ctx.lineWidth = 1.5;
                                    ctx.strokeStyle = rgba(color, 0.55);
                                    ctx.stroke();
                                }

                                function paintCanvas(ctx) {
                                    ctx.clearRect(0, 0, curveCanvas.width, curveCanvas.height);

                                    ctx.lineWidth = 1;
                                    ctx.strokeStyle = rgba(Theme.outline, 0.28);
                                    for (let temp = tempMin + tempStep; temp <= tempMax; temp += tempStep) {
                                        const x = xFor(temp);
                                        ctx.beginPath();
                                        ctx.moveTo(x, padTop);
                                        ctx.lineTo(x, padTop + plotH);
                                        ctx.stroke();
                                    }
                                    for (let percent = 0; percent <= 100; percent += 20) {
                                        const y = yFor(percent);
                                        ctx.beginPath();
                                        ctx.moveTo(padLeft, y);
                                        ctx.lineTo(padLeft + plotW, y);
                                        ctx.stroke();
                                    }

                                    ctx.fillStyle = rgba(Theme.surfaceVariantText, 1);
                                    ctx.font = "10px sans-serif";
                                    ctx.textAlign = "right";
                                    ctx.textBaseline = "middle";
                                    for (let percent = 0; percent <= 100; percent += 20)
                                        ctx.fillText(percent + "%", padLeft - 5, yFor(percent));

                                    ctx.textAlign = "center";
                                    ctx.textBaseline = "top";
                                    for (let temp = tempMin + tempStep; temp <= tempMax; temp += tempStep)
                                        ctx.fillText(temp + "°", xFor(temp), padTop + plotH + 4);

                                    const cpuActive = root.curveTarget === 0;
                                    if (cpuActive)
                                        fillCurve(ctx, root.curveCpuTemps, root.curveCpuSpeeds, Theme.primary, 0.2);
                                    else
                                        fillCurve(ctx, root.curveGpuTemps, root.curveGpuSpeeds, Theme.tertiary, 0.2);

                                    strokeCurve(ctx, root.curveGpuTemps, root.curveGpuSpeeds, cpuActive ? 0.3 : 1, Theme.tertiary, !cpuActive, cpuActive ? 1.5 : 2.5);
                                    strokeCurve(ctx, root.curveCpuTemps, root.curveCpuSpeeds, cpuActive ? 1 : 0.3, Theme.primary, cpuActive, cpuActive ? 2.5 : 1.5);
                                }

                                function clampSpeed(speeds, index, percent) {
                                    const low = index > 0 ? speeds[index - 1] : 0;
                                    const high = index < 6 ? speeds[index + 1] : 100;
                                    return Math.max(low, Math.min(high, percent));
                                }

                                function dragHandle(index, mouseX, mouseY) {
                                    let percent = Math.round(percentFor(mouseY) / 5) * 5;
                                    percent = Math.max(0, Math.min(100, percent));

                                    const temps = root.curveTemps.slice();
                                    const speeds = root.curveSpeeds.slice();

                                    if (index >= 1) {
                                        let temp = Math.round(tempFor(mouseX));
                                        temp = Math.max(tempMin + 1, Math.min(tempMax, temp));
                                        if (index >= 2)
                                            temp = Math.max(temp, temps[index - 2] + 1);
                                        if (index <= 5)
                                            temp = Math.min(temp, temps[index] - 1);
                                        temps[index - 1] = temp;
                                    }

                                    speeds[index] = clampSpeed(speeds, index, percent);
                                    activeHandle = index;
                                    hoverHandle = -1;
                                    root.setCurve(temps, speeds);
                                    curveCanvas.requestPaint();
                                }

                                function nearest(mouseX, mouseY) {
                                    let best = -1;
                                    let bestDistance = 28 * 28;
                                    for (let index = 0; index <= 6; index++) {
                                        const point = handlePos(root.curveTemps, root.curveSpeeds, index);
                                        const dx = point.x - mouseX;
                                        const dy = point.y - mouseY;
                                        const distance = dx * dx + dy * dy;
                                        if (distance < bestDistance) {
                                            bestDistance = distance;
                                            best = index;
                                        }
                                    }
                                    return best;
                                }

                                Connections {
                                    target: root

                                    function onCurveCpuTempsChanged() {
                                        curveCanvas.requestPaint();
                                    }

                                    function onCurveCpuSpeedsChanged() {
                                        curveCanvas.requestPaint();
                                    }

                                    function onCurveGpuTempsChanged() {
                                        curveCanvas.requestPaint();
                                    }

                                    function onCurveGpuSpeedsChanged() {
                                        curveCanvas.requestPaint();
                                    }

                                    function onCurveTargetChanged() {
                                        curveCanvas.requestPaint();
                                    }
                                }

                                Canvas {
                                    id: curveCanvas

                                    anchors.fill: parent
                                    renderStrategy: Canvas.Cooperative
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    onPaint: graph.paintCanvas(getContext("2d"))
                                }

                                MouseArea {
                                    id: curveDrag

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: graph.hoverHandle >= 0 || graph.activeHandle >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: root.curveReady

                                    onPressed: mouse => {
                                        graph.activeHandle = graph.nearest(mouse.x, mouse.y);
                                        if (graph.activeHandle >= 0)
                                            graph.dragHandle(graph.activeHandle, mouse.x, mouse.y);
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed && graph.activeHandle >= 0) {
                                            graph.dragHandle(graph.activeHandle, mouse.x, mouse.y);
                                            return;
                                        }
                                        graph.hoverHandle = graph.nearest(mouse.x, mouse.y);
                                    }
                                    onReleased: graph.activeHandle = -1
                                    onCanceled: graph.activeHandle = -1
                                    onExited: graph.hoverHandle = -1
                                }
                            }
                        }
                    }

                    DCard {
                        width: parent.width
                        height: curveControlsColumn.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: curveControlsColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Curve target")
                            }

                            DButtonGroup {
                                width: parent.width
                                fillWidth: true
                                size: "small"
                                checkEnabled: false
                                maximumWidth: parent.width
                                model: [
                                    {
                                        "text": I18n.trFor("dankFanStats", "CPU"),
                                        "icon": "memory"
                                    },
                                    {
                                        "text": I18n.trFor("dankFanStats", "GPU"),
                                        "icon": "developer_board"
                                    }
                                ]
                                currentIndex: root.curveTarget
                                onSelectionChanged: (index, selected) => {
                                    if (selected) {
                                        root.curveTarget = index;
                                        curveCanvas.requestPaint();
                                    }
                                }
                            }

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Presets")
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                Repeater {
                                    model: [
                                        {
                                            "label": I18n.trFor("dankFanStats", "Silent"),
                                            "name": "silent"
                                        },
                                        {
                                            "label": I18n.trFor("dankFanStats", "Balanced"),
                                            "name": "balanced"
                                        },
                                        {
                                            "label": I18n.trFor("dankFanStats", "Performance"),
                                            "name": "performance"
                                        }
                                    ]

                                    DButton {
                                        required property var modelData

                                        width: (parent.width - parent.spacing * 2) / 3
                                        buttonHeight: Theme.buttonHeightXS
                                        text: modelData.label
                                        backgroundColor: Theme.secondaryContainer
                                        textColor: Theme.onSecondaryContainer
                                        enabled: root.curveReady
                                        onClicked: root.applyPreset(modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DButton {
                            width: (parent.width - parent.spacing) / 2
                            text: I18n.trFor("dankFanStats", "Reset")
                            iconName: "restart_alt"
                            backgroundColor: Theme.secondaryContainer
                            textColor: Theme.onSecondaryContainer
                            enabled: root.curveReady
                            onClicked: root.resetCurve()
                        }

                        DButton {
                            width: (parent.width - parent.spacing) / 2
                            text: I18n.trFor("dankFanStats", "Apply curve")
                            iconName: "check"
                            enabled: root.curveReady && (root.curveDirty || !root.advancedOn)
                            onClicked: root.applyCurve()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 3

                    DCard {
                        width: parent.width
                        height: keyboardColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.kbdBacklightSupported && root.kbdLabels.length > 0

                        Column {
                            id: keyboardColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Keyboard backlight")
                            }

                            DButtonGroup {
                                width: parent.width
                                fillWidth: true
                                size: "small"
                                checkEnabled: false
                                maximumWidth: parent.width
                                model: root.kbdLabels
                                currentIndex: root.kbdBacklight
                                onSelectionChanged: (index, selected) => {
                                    if (selected)
                                        root.setKbdBacklight(index);
                                }
                            }
                        }
                    }

                    DCard {
                        width: parent.width
                        height: functionColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.functionKeysSupported

                        Column {
                            id: functionColumn
                            width: parent.width
                            spacing: Theme.spacingS

                            SectionTitle {
                                text: I18n.trFor("dankFanStats", "Function keys")
                            }

                            DButtonGroup {
                                width: parent.width
                                fillWidth: true
                                size: "small"
                                checkEnabled: false
                                maximumWidth: parent.width
                                model: [
                                    I18n.trFor("dankFanStats", "Fn left"),
                                    I18n.trFor("dankFanStats", "Fn right")
                                ]
                                currentIndex: root.fnKey === "right" ? 1 : 0
                                onSelectionChanged: (index, selected) => {
                                    if (selected)
                                        root.setKeySwap(index === 1);
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: I18n.trFor("dankFanStats", "The Windows key takes the opposite side.")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: errorText.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadiusM
                    color: Theme.errorContainer
                    visible: root.errorText.length > 0

                    StyledText {
                        id: errorText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        text: root.errorText
                        color: Theme.onErrorContainer
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
