import QtQuick
import Quickshell
import Quickshell.Io

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // --- settings (persisted through pluginData) ---
    property string statsPath: pluginData.statsPath || "/run/dank-fan-stats/stats.json"
    property string controlPath: pluginData.controlPath || "/run/dank-fan-stats/control"
    property int updateInterval: parseInt(pluginData.updateInterval) || 3000

    property color boostColor: "#FF9800"

    // --- live state ---
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

    // --- popout tab + fan curve state ---
    property int tabIndex: 0
    property var curveCpuTemps: [50, 60, 65, 70, 75, 80]
    property var curveCpuSpeeds: [0, 40, 50, 60, 70, 80, 85]
    property var curveGpuTemps: [50, 60, 65, 70, 75, 80]
    property var curveGpuSpeeds: [0, 40, 50, 60, 70, 80, 85]
    property int curveTarget: 0 // 0 = CPU, 1 = GPU
    property bool curveDirty: false

    readonly property bool advancedOn: root.fanMode === "advanced"
    readonly property bool boostOn: root.coolerBoost === "on"
    readonly property var kbdLabels: {
        const n = root.kbdBacklightMax;
        if (n <= 0)
            return [];
        if (n === 3)
            return ["Off", "Low", "Medium", "High"];
        const out = ["Off"];
        for (let i = 1; i <= n; i++)
            out.push(String(i));
        return out;
    }
    readonly property var curveTemps: curveTarget === 0 ? curveCpuTemps : curveGpuTemps
    readonly property var curveSpeeds: curveTarget === 0 ? curveCpuSpeeds : curveGpuSpeeds

    // Small selectable chip used by the curve and keyboard tabs. Gives its label
    // generous width so it renders cleanly with any font metrics.
    component Chip: StyledRect {
        id: chip

        property string label: ""
        property bool selected: false
        signal activated

        implicitWidth: chipLabel.implicitWidth + Theme.spacingM * 2
        implicitHeight: 30
        radius: Theme.cornerRadius
        color: chip.selected ? Theme.primary : "transparent"
        border.width: chip.selected ? 0 : 1
        border.color: Theme.outline

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Theme.fontSizeSmall
            color: chip.selected ? Theme.primaryText : Theme.surfaceText
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }
    }

    // compact telemetry: three columns
    readonly property var telemetry: [
        {
            "label": "CPU",
            "value": root.cpuTemp + "°C",
            "sub": root.cpuFan + "% fan"
        },
        {
            "label": "GPU",
            "value": root.gpuTemp + "°C",
            "sub": root.gpuFan + "% fan"
        },
        {
            "label": "FAN",
            "value": root.fanRpm >= 1000 ? (root.fanRpm / 1000).toFixed(1) + "k" : (root.fanRpm > 0 ? String(root.fanRpm) : "--"),
            "sub": "RPM"
        }
    ]

    readonly property var toggleItems: [
        {
            "key": "cooler_boost",
            "label": "Cooler Boost"
        },
        {
            "key": "super_battery",
            "label": "Super Battery"
        },
        {
            "key": "webcam",
            "label": "Camera"
        },
        {
            "key": "webcam_block",
            "label": "Block Camera"
        }
    ]

    function statColor() {
        return root.boostOn ? root.boostColor : Theme.surfaceText;
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

    function parseOutput(output) {
        const cleaned = output.trim();

        if (cleaned.length === 0) {
            root.statsAvailable = false;
            root.errorText = "No stats file content yet";
            return;
        }

        let data = null;
        try {
            data = JSON.parse(cleaned);
        } catch (e) {
            root.statsAvailable = false;
            root.errorText = "Stats JSON parse failed";
            return;
        }

        root.statsAvailable = !!data.ok;
        root.errorText = data.ok ? "" : (data.error || "Stats service reported an error");

        root.fanRpm = parseInt(data.fanRpm) || 0;
        root.cpuTemp = parseInt(data.cpuTemp) || 0;
        root.gpuTemp = parseInt(data.gpuTemp) || 0;
        root.cpuFan = parseInt(data.cpuFan) || 0;
        root.gpuFan = parseInt(data.gpuFan) || 0;
        root.fwVersion = data.fwVersion || "";

        root.coolerBoost = (data.coolerBoost || "off").toString().toLowerCase();
        root.superBattery = (data.superBattery || "off").toString().toLowerCase();
        root.webcam = (data.webcam || "").toString().toLowerCase();
        root.webcamBlock = (data.webcamBlock || "").toString().toLowerCase();
        root.shiftModes = data.shiftModes || [];
        root.fanModes = data.fanModes || [];
        if (data.shiftMode !== undefined)
            root.shiftMode = (data.shiftMode || "").toString();
        if (data.fanMode !== undefined)
            root.fanMode = (data.fanMode || "").toString();
        root.fnKey = (data.fnKey || "").toString().toLowerCase();
        root.winKey = (data.winKey || "").toString().toLowerCase();
        root.chargeStart = parseInt(data.chargeStart) || 0;
        root.chargeEnd = parseInt(data.chargeEnd) || 100;
        root.kbdBacklight = parseInt(data.kbdBacklight) || 0;
        root.kbdBacklightMax = parseInt(data.kbdBacklightMax) || 0;

        // Mirror the EC curve unless the user is mid-edit.
        const c = data.curve;
        if (c && !root.curveDirty) {
            if (Array.isArray(c.cpuTemps) && c.cpuTemps.length === 6)
                root.curveCpuTemps = c.cpuTemps.map(Number);
            if (Array.isArray(c.cpuSpeeds) && c.cpuSpeeds.length === 7)
                root.curveCpuSpeeds = c.cpuSpeeds.map(Number);
            if (Array.isArray(c.gpuTemps) && c.gpuTemps.length === 6)
                root.curveGpuTemps = c.gpuTemps.map(Number);
            if (Array.isArray(c.gpuSpeeds) && c.gpuSpeeds.length === 7)
                root.curveGpuSpeeds = c.gpuSpeeds.map(Number);
        }
    }

    function sendCommand(command) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", command, root.controlPath]);
    }

    function setMode(kind, value) {
        if (!value)
            return;
        if (kind === "shift_mode")
            root.shiftMode = value;
        else if (kind === "fan_mode")
            root.fanMode = value;
        root.sendCommand("set " + kind + " " + value);
    }

    function setToggle(key, enabled) {
        const value = enabled ? "on" : "off";
        if (key === "cooler_boost")
            root.coolerBoost = value;
        else if (key === "super_battery")
            root.superBattery = value;
        else if (key === "webcam")
            root.webcam = value;
        else if (key === "webcam_block")
            root.webcamBlock = value;
        root.sendCommand("set " + key + " " + value);
    }

    function setKeySwap(swapped) {
        const fn = swapped ? "right" : "left";
        const win = swapped ? "left" : "right";
        root.fnKey = fn;
        root.winKey = win;
        root.sendCommand("set fn_key " + fn);
        root.sendCommand("set win_key " + win);
    }

    function setKbdBacklight(value) {
        root.kbdBacklight = value;
        root.sendCommand("set kbd_backlight " + value);
    }

    function setCharge(key, value) {
        if (key === "charge_start") {
            root.chargeStart = value;
            if (root.chargeEnd <= value)
                root.chargeEnd = Math.min(100, value + 5);
        } else {
            root.chargeEnd = value;
            if (root.chargeStart >= value)
                root.chargeStart = Math.max(0, value - 5);
        }
        root.sendCommand("set " + key + " " + value);
    }

    // --- fan curve ------------------------------------------------------------
    function curveCommand() {
        return "set fan_curve " + root.curveCpuTemps.join(",") + " " + root.curveCpuSpeeds.join(",") + " " + root.curveGpuTemps.join(",") + " " + root.curveGpuSpeeds.join(",");
    }

    function applyCurve() {
        root.sendCommand(root.curveCommand());
        root.sendCommand("set advanced on");
        root.fanMode = "advanced";
        root.curveDirty = false;
    }

    function setAdvanced(enabled) {
        if (enabled) {
            root.sendCommand(root.curveCommand());
            root.sendCommand("set advanced on");
            root.fanMode = "advanced";
            root.curveDirty = false;
        } else {
            root.sendCommand("set advanced off");
            root.fanMode = "auto";
        }
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
        let t, s;
        if (name === "silent") {
            t = [60, 65, 70, 75, 80, 85];
            s = [0, 25, 35, 45, 55, 65, 75];
        } else if (name === "performance") {
            t = [45, 50, 55, 60, 65, 70];
            s = [30, 45, 60, 75, 85, 95, 100];
        } else {
            t = [50, 60, 65, 70, 75, 80];
            s = [0, 40, 50, 60, 70, 80, 85];
        }
        root.curveCpuTemps = t.slice();
        root.curveCpuSpeeds = s.slice();
        root.curveGpuTemps = t.slice();
        root.curveGpuSpeeds = s.slice();
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

    // left click opens the control menu, right click quick-toggles cooler boost
    pillClickAction: null
    pillRightClickAction: () => root.sendCommand("toggle cooler_boost")

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

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
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

            DankIcon {
                name: "mode_fan"
                size: Theme.fontSizeSmall
                color: root.statsAvailable ? root.statColor() : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.statsAvailable ? `${root.fanRpm}` : "--"
                color: root.statsAvailable ? Theme.surfaceText : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 0

    popoutContent: Component {
        PopoutComponent {
            id: menu

            property var parentPopout: null

            width: parent ? parent.width : 0
            headerText: "MSI EC Control"
            detailsText: root.statsAvailable ? ((root.shiftMode || "MSI controller") + (root.fwVersion.length > 0 ? "  ·  " + root.fwVersion : "")) : (root.errorText || "Waiting for the fan daemon…")
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    iconName: "refresh"
                    iconSize: Theme.iconSizeSmall
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.iconSizeSmall + 8
                    tooltipText: "Refresh"
                    onClicked: root.sendCommand("refresh")
                }
            }

            // Sliders live in this component scope; keep them synced with the
            // daemon (dragging assigns `value`, which breaks a plain binding).
            Connections {
                target: root

                function onChargeStartChanged() {
                    chargeStartSlider.value = root.chargeStart;
                }

                function onChargeEndChanged() {
                    chargeEndSlider.value = root.chargeEnd;
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // --- tabs -----------------------------------------------------
                Item {
                    width: parent.width
                    height: tabBar.height + 14

                    DankTabBar {
                        id: tabBar
                        anchors.top: parent.top
                        width: parent.width
                        height: 44
                        tabHeight: 44
                        spacing: Theme.spacingXS
                        currentIndex: root.tabIndex
                        model: [
                            {
                                "text": "Stats",
                                "icon": "thermostat"
                            },
                            {
                                "text": "Settings",
                                "icon": "tune"
                            },
                            {
                                "text": "Curve",
                                "icon": "show_chart"
                            },
                            {
                                "text": "Keyboard",
                                "icon": "keyboard"
                            }
                        ]
                        onTabClicked: index => {
                            root.tabIndex = index;
                            if (index === 2)
                                curveCanvas.requestPaint();
                        }
                    }
                }

                // ================= STATS ======================================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 0

                    StyledRect {
                        width: parent.width
                        height: telemetryRow.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Row {
                            id: telemetryRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingM

                            Repeater {
                                model: root.telemetry

                                delegate: Column {
                                    width: (telemetryRow.width - telemetryRow.spacing * 2) / 3
                                    spacing: 2

                                    StyledText {
                                        text: modelData.label
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    StyledText {
                                        text: modelData.value
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        text: modelData.sub
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "System"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            bottomPadding: 2
                        }

                        Repeater {
                            model: [
                                {
                                    "label": "Performance mode",
                                    "value": root.shiftMode || "-"
                                },
                                {
                                    "label": "Fan mode",
                                    "value": root.fanMode || "-"
                                },
                                {
                                    "label": "Firmware",
                                    "value": root.fwVersion || "-"
                                },
                                {
                                    "label": "Daemon",
                                    "value": root.statsAvailable ? "online" : "offline"
                                }
                            ]

                            delegate: Row {
                                width: parent.width
                                spacing: Theme.spacingM

                                StyledText {
                                    width: parent.width - infoValue.implicitWidth - parent.spacing
                                    text: modelData.label
                                    elide: Text.ElideRight
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    id: infoValue
                                    text: modelData.value
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }

                // ================= SETTINGS ===================================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 1

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.shiftModes.length > 0

                        StyledText {
                            text: "Performance mode"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                        }

                        DankButtonGroup {
                            size: "small"
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
                        spacing: Theme.spacingS
                        visible: root.fanModes.length > 0

                        StyledText {
                            text: "Fan mode"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                        }

                        DankButtonGroup {
                            size: "small"
                            maximumWidth: parent.width
                            model: root.fanModes
                            currentIndex: root.fanModes.indexOf(root.fanMode)
                            onSelectionChanged: (index, selected) => {
                                if (selected)
                                    root.setMode("fan_mode", root.fanModes[index]);
                            }
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        rowSpacing: Theme.spacingS
                        columnSpacing: Theme.spacingM

                        Repeater {
                            model: root.toggleItems

                            delegate: Item {
                                width: (parent.width - Theme.spacingM) / 2
                                height: 34

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 62
                                    text: modelData.label
                                    elide: Text.ElideRight
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                }

                                DankToggle {
                                    hideText: true
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: root.toggleState(modelData.key)
                                    onToggled: checked => root.setToggle(modelData.key, checked)
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            StyledText {
                                width: parent.width - chargeRange.implicitWidth - parent.spacing
                                text: "Battery charge limit"
                                elide: Text.ElideRight
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                            }

                            StyledText {
                                id: chargeRange
                                text: root.chargeStart + "% - " + root.chargeEnd + "%"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        DankSlider {
                            id: chargeStartSlider
                            width: parent.width
                            minimum: 0
                            maximum: 100
                            step: 5
                            value: root.chargeStart
                            leftIcon: "battery_charging_full"
                            onSliderDragFinished: finalValue => root.setCharge("charge_start", finalValue)
                        }

                        DankSlider {
                            id: chargeEndSlider
                            width: parent.width
                            minimum: 0
                            maximum: 100
                            step: 5
                            value: root.chargeEnd
                            rightIcon: "battery_full"
                            onSliderDragFinished: finalValue => root.setCharge("charge_end", finalValue)
                        }
                    }
                }

                // ================= CURVE ======================================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 2

                    DankToggle {
                        width: parent.width
                        text: "Advanced fan control"
                        description: root.advancedOn ? "Active - the EC is following this curve" : "Off - the EC uses its automatic curve"
                        checked: root.advancedOn
                        onToggled: checked => root.setAdvanced(checked)
                    }

                    Item {
                        id: graph
                        width: parent.width
                        height: 200

                        readonly property real padLeft: 30
                        readonly property real padRight: 10
                        readonly property real padTop: 10
                        readonly property real padBottom: 20
                        readonly property real plotW: Math.max(1, width - padLeft - padRight)
                        readonly property real plotH: Math.max(1, height - padTop - padBottom)
                        readonly property real tempMin: 30
                        readonly property real tempMax: 100
                        readonly property real tempStep: 10

                        function xFor(t) {
                            return padLeft + (t - tempMin) / (tempMax - tempMin) * plotW;
                        }

                        function yFor(p) {
                            return padTop + (1 - p / 100) * plotH;
                        }

                        function tempFor(x) {
                            return tempMin + (x - padLeft) / plotW * (tempMax - tempMin);
                        }

                        function pctFor(y) {
                            return (1 - (y - padTop) / plotH) * 100;
                        }

                        // handle 0 = level below the first threshold, 1..6 = level at threshold k
                        function handlePos(temps, speeds, k) {
                            return k === 0 ? Qt.point(xFor(tempMin), yFor(speeds[0])) : Qt.point(xFor(temps[k - 1]), yFor(speeds[k]));
                        }

                        function rgba(c, a) {
                            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")";
                        }

                        function strokeCurve(ctx, temps, speeds, alpha, color, handles) {
                            ctx.beginPath();
                            ctx.moveTo(xFor(tempMin), yFor(speeds[0]));
                            for (let k = 1; k <= 6; k++) {
                                const xk = xFor(temps[k - 1]);
                                ctx.lineTo(xk, yFor(speeds[k - 1]));
                                ctx.lineTo(xk, yFor(speeds[k]));
                            }
                            ctx.lineTo(xFor(tempMax), yFor(speeds[6]));
                            ctx.lineWidth = 2;
                            ctx.lineJoin = "round";
                            ctx.strokeStyle = rgba(color, alpha);
                            ctx.stroke();

                            if (handles) {
                                ctx.fillStyle = rgba(color, 1);
                                for (let k = 0; k <= 6; k++) {
                                    const pt = handlePos(temps, speeds, k);
                                    ctx.beginPath();
                                    ctx.arc(pt.x, pt.y, 5, 0, Math.PI * 2);
                                    ctx.fill();
                                }
                            }
                        }

                        function paintCanvas(ctx) {
                            ctx.clearRect(0, 0, curveCanvas.width, curveCanvas.height);

                            ctx.lineWidth = 1;
                            ctx.strokeStyle = rgba(Theme.outline, 0.35);
                            for (let t = tempMin + tempStep; t <= tempMax; t += tempStep) {
                                const x = xFor(t);
                                ctx.beginPath();
                                ctx.moveTo(x, padTop);
                                ctx.lineTo(x, padTop + plotH);
                                ctx.stroke();
                            }
                            for (let p = 0; p <= 100; p += 20) {
                                const y = yFor(p);
                                ctx.beginPath();
                                ctx.moveTo(padLeft, y);
                                ctx.lineTo(padLeft + plotW, y);
                                ctx.stroke();
                            }

                            ctx.fillStyle = rgba(Theme.surfaceVariantText, 1);
                            ctx.font = "10px sans-serif";
                            ctx.textAlign = "right";
                            ctx.textBaseline = "middle";
                            for (let p = 0; p <= 100; p += 20)
                                ctx.fillText(p + "%", padLeft - 4, yFor(p));
                            ctx.textAlign = "center";
                            ctx.textBaseline = "top";
                            for (let t = tempMin + tempStep; t <= tempMax; t += tempStep)
                                ctx.fillText(t + "°", xFor(t), padTop + plotH + 3);

                            const cpuActive = root.curveTarget === 0;
                            strokeCurve(ctx, root.curveGpuTemps, root.curveGpuSpeeds, cpuActive ? 0.3 : 1, Theme.tertiary, !cpuActive);
                            strokeCurve(ctx, root.curveCpuTemps, root.curveCpuSpeeds, cpuActive ? 1 : 0.3, Theme.primary, cpuActive);
                        }

                        function clampSpeed(speeds, k, pct) {
                            const lo = k > 0 ? speeds[k - 1] : 0;
                            const hi = k < 6 ? speeds[k + 1] : 100;
                            return Math.max(lo, Math.min(hi, pct));
                        }

                        function dragHandle(k, mx, my) {
                            let pct = Math.round(pctFor(my) / 5) * 5;
                            pct = Math.max(0, Math.min(100, pct));

                            const temps = root.curveTemps.slice();
                            const speeds = root.curveSpeeds.slice();

                            if (k >= 1) {
                                let t = Math.round(tempFor(mx));
                                t = Math.max(tempMin + 1, Math.min(tempMax, t));
                                if (k >= 2)
                                    t = Math.max(t, temps[k - 2] + 1);
                                if (k <= 5)
                                    t = Math.min(t, temps[k] - 1);
                                temps[k - 1] = t;
                            }
                            speeds[k] = clampSpeed(speeds, k, pct);
                            root.setCurve(temps, speeds);
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
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: graph.paintCanvas(getContext("2d"))
                        }

                        MouseArea {
                            id: curveDrag
                            anchors.fill: parent
                            property int activeHandle: -1

                            function nearest(mx, my) {
                                const temps = root.curveTemps;
                                const speeds = root.curveSpeeds;
                                let best = -1;
                                let bestDist = 26 * 26;
                                for (let k = 0; k <= 6; k++) {
                                    const p = graph.handlePos(temps, speeds, k);
                                    const dx = p.x - mx;
                                    const dy = p.y - my;
                                    const d = dx * dx + dy * dy;
                                    if (d < bestDist) {
                                        bestDist = d;
                                        best = k;
                                    }
                                }
                                return best;
                            }

                            onPressed: mouse => {
                                curveDrag.activeHandle = curveDrag.nearest(mouse.x, mouse.y);
                                if (curveDrag.activeHandle >= 0)
                                    graph.dragHandle(curveDrag.activeHandle, mouse.x, mouse.y);
                            }
                            onPositionChanged: mouse => {
                                if (pressed && curveDrag.activeHandle >= 0)
                                    graph.dragHandle(curveDrag.activeHandle, mouse.x, mouse.y);
                            }
                            onReleased: curveDrag.activeHandle = -1
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "Curve target"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            Chip {
                                label: "CPU"
                                selected: root.curveTarget === 0
                                onActivated: {
                                    root.curveTarget = 0;
                                    curveCanvas.requestPaint();
                                }
                            }

                            Chip {
                                label: "GPU"
                                selected: root.curveTarget === 1
                                onActivated: {
                                    root.curveTarget = 1;
                                    curveCanvas.requestPaint();
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "Presets"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            Chip {
                                label: "Silent"
                                onActivated: root.applyPreset("silent")
                            }

                            Chip {
                                label: "Balanced"
                                onActivated: root.applyPreset("balanced")
                            }

                            Chip {
                                label: "Performance"
                                onActivated: root.applyPreset("performance")
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 32

                        Chip {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Reset to factory"
                            onActivated: root.resetCurve()
                        }

                        Chip {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Apply curve"
                            selected: true
                            onActivated: root.applyCurve()
                        }
                    }
                }

                // ================= KEYBOARD ===================================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tabIndex === 3

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.kbdLabels.length > 0

                        StyledText {
                            text: "Keyboard backlight"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                        }

                        DankButtonGroup {
                            size: "small"
                            maximumWidth: parent.width
                            model: root.kbdLabels
                            currentIndex: root.kbdBacklight
                            onSelectionChanged: (index, selected) => {
                                if (selected)
                                    root.setKbdBacklight(index);
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Fn / Windows key position"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            Chip {
                                width: (parent.width - parent.spacing) / 2
                                label: "Fn left / Win right"
                                selected: root.fnKey !== "right"
                                onActivated: root.setKeySwap(false)
                            }

                            Chip {
                                width: (parent.width - parent.spacing) / 2
                                label: "Fn right / Win left"
                                selected: root.fnKey === "right"
                                onActivated: root.setKeySwap(true)
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: root.errorText.length > 0
                    text: root.errorText
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
