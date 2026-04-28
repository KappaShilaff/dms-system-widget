import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginComponent {
    id: root

    layerNamespacePlugin: "dms-system-plugin"
    popoutWidth: 980
    popoutHeight: 660

    property var cpuUsageHistory: []
    property double lastCpuUsageSampleMs: 0
    property string activeDetail: ""
    property string searchText: ""
    property string expandedPid: ""
    property string processFilter: "all"
    property var cpuFreqInfo: ({
        "avg_mhz": 0,
        "max_mhz": 0,
        "epp": "",
        "epp_available": [],
        "cores": []
    })

    Component.onCompleted: {
        DgopService.addRef(["network", "processes", "cpu", "memory", "system"]);
        refreshCpuFrequencies();
    }

    Component.onDestruction: {
        DgopService.removeRef(["network", "processes", "cpu", "memory", "system"]);
    }

    function formatMem(kb) {
        const value = Math.max(0, kb || 0);
        if (value < 1024)
            return value.toFixed(0) + " KB";
        if (value < 1024 * 1024)
            return (value / 1024).toFixed(value >= 100 * 1024 ? 0 : 1) + " MB";
        return (value / (1024 * 1024)).toFixed(value >= 10 * 1024 * 1024 ? 0 : 1) + " GB";
    }

    function wholeGb(kb) {
        return (Math.max(0, kb || 0) / (1024 * 1024)).toFixed(0);
    }

    function formatSpeed(bytesPerSec) {
        const value = Math.max(0, bytesPerSec || 0);
        if (value < 1024)
            return value.toFixed(0) + " B";
        if (value < 1024 * 1024) {
            const kb = value / 1024;
            return (kb >= 1000 ? kb.toFixed(0) : kb.toFixed(1)) + " KB";
        }
        return (value / (1024 * 1024)).toFixed(1) + " MB";
    }

    function formatFreq(mhz) {
        if (!isFinite(mhz) || mhz <= 0)
            return "--";
        if (mhz >= 1000)
            return (mhz / 1000).toFixed(2) + " GHz";
        return Math.round(mhz) + " MHz";
    }

    function cpuAccent(usage) {
        if (!isFinite(usage))
            return Theme.primary;
        if (usage >= 85)
            return "#ff6b6b";
        if (usage >= 65)
            return "#ff9f43";
        if (usage >= 45)
            return "#ffd43b";
        if (usage >= 25)
            return "#51cf66";
        return Theme.primary;
    }

    function appendCpuUsageSample() {
        const now = Date.now();
        let history = cpuUsageHistory.slice();
        if (lastCpuUsageSampleMs > 0) {
            const missingSamples = Math.min(60, Math.floor((now - lastCpuUsageSampleMs) / 1000) - 1);
            for (let i = 0; i < missingSamples; i++)
                history.push(null);
        }
        const usage = DgopService.cpuUsage;
        history.push(isFinite(usage) ? Math.max(0, Math.min(100, usage)) : null);
        cpuUsageHistory = history.slice(-60);
        lastCpuUsageSampleMs = now;
    }

    function refreshCpuFrequencies() {
        if (!cpuFreqProcess.running)
            cpuFreqProcess.running = true;
    }

    function gpuResidentKb() {
        let total = 0;
        const processes = DgopService.allProcesses || [];
        for (const proc of processes)
            total += proc.gpuResidentKB || proc.gpuMemoryKB || 0;
        return total;
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            StyledText {
                text: "CPU " + DgopService.cpuUsage.toFixed(0) + "%"
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.wholeGb(DgopService.usedMemoryKB) + " GB"
                color: Theme.widgetTextColor
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1

            StyledText {
                text: DgopService.cpuUsage.toFixed(0) + "%"
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.wholeGb(DgopService.usedMemoryKB)
                color: Theme.widgetTextColor
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        Rectangle {
            id: popoutRoot

            implicitHeight: 640
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "monitoring"
                        size: Theme.iconSizeLarge
                        color: Theme.primary
                    }

                    StyledText {
                        text: "Niri System"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    DankTextField {
                        Layout.preferredWidth: 420
                        Layout.preferredHeight: Theme.fontSizeMedium * 2.5
                        placeholderText: "Search..."
                        leftIconName: "search"
                        showClearButton: true
                        text: root.searchText
                        onTextChanged: root.searchText = text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    StatCard {
                        Layout.fillWidth: true
                        title: "CPU"
                        value: DgopService.cpuUsage.toFixed(0) + "%"
                        unit: DgopService.cpuTemperature > 0 ? DgopService.cpuTemperature.toFixed(0) + "°" : ""
                        active: root.activeDetail === "cpu"
                        sparklineValues: root.cpuUsageHistory
                        accentColor: root.cpuAccent(DgopService.cpuUsage)
                        onClicked: {
                            root.activeDetail = root.activeDetail === "cpu" ? "" : "cpu";
                            root.refreshCpuFrequencies();
                        }
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "GPU"
                        value: root.formatMem(root.gpuResidentKb()).replace(" GB", "")
                        unit: "GB"
                        active: root.activeDetail === "gpu"
                        accentColor: Theme.primary
                        onClicked: root.activeDetail = root.activeDetail === "gpu" ? "" : "gpu"
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "RAM"
                        value: root.wholeGb(DgopService.usedMemoryKB)
                        unit: "/" + root.wholeGb(DgopService.totalMemoryKB) + " GB"
                        accentColor: Theme.secondary
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Swap"
                        value: root.wholeGb(DgopService.usedSwapKB)
                        unit: "/" + root.wholeGb(DgopService.totalSwapKB) + " GB"
                        accentColor: Theme.info
                    }
                }

                CpuDetails {
                    Layout.fillWidth: true
                    visible: root.activeDetail === "cpu"
                    cpuInfo: root.cpuFreqInfo
                }

                NetworkDetails {
                    Layout.fillWidth: true
                    visible: root.activeDetail === "gpu"
                }

                Row {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    Repeater {
                        model: ["All", "User", "System"]

                        Rectangle {
                            width: 72
                            height: 32
                            radius: Theme.cornerRadius
                            color: {
                                const value = modelData.toLowerCase();
                                return root.processFilter === value ? Theme.primary : Theme.surfaceContainerHigh;
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData
                                color: root.processFilter === modelData.toLowerCase() ? Theme.surface : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.processFilter = modelData.toLowerCase()
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                    clip: true

                    ProcessesView {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        searchText: root.searchText
                        expandedPid: root.expandedPid
                        processFilter: root.processFilter
                        contextMenu: processContextMenu
                        onExpandedPidChanged: root.expandedPid = expandedPid
                    }
                }
            }

            ProcessContextMenu {
                id: processContextMenu
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.appendCpuUsageSample()
    }

    Timer {
        interval: 2000
        running: root.activeDetail === "cpu"
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshCpuFrequencies()
    }

    Process {
        id: cpuFreqProcess
        command: ["python3", Quickshell.env("HOME") + "/.config/DankMaterialShell/plugins/DmsSystemPlugin/scripts/cpu-frequencies.py"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.cpuFreqInfo = JSON.parse(line);
                } catch (e) {
                    console.warn("DmsSystemPlugin: failed to parse CPU frequency info", e);
                }
            }
        }
    }

    component StatCard: Rectangle {
        id: card

        signal clicked

        property string title: ""
        property string value: ""
        property string unit: ""
        property bool active: false
        property color accentColor: Theme.primary
        property var sparklineValues: []

        height: 94
        radius: Theme.cornerRadius
        color: active ? Theme.withAlpha(accentColor, 0.14) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: active ? 2 : 1
        border.color: Theme.withAlpha(accentColor, active ? 0.65 : 0.28)

        Canvas {
            id: sparklineCanvas
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.spacingS
            height: 22
            visible: card.sparklineValues.length > 1

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const values = card.sparklineValues || [];
                if (values.length < 2)
                    return;

                const pad = 3;
                const step = (width - pad * 2) / Math.max(1, values.length - 1);
                ctx.lineWidth = 2;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.strokeStyle = card.accentColor;
                ctx.beginPath();
                let started = false;
                for (let i = 0; i < values.length; i++) {
                    const raw = values[i];
                    if (raw === null || raw === undefined || !isFinite(raw)) {
                        started = false;
                        continue;
                    }
                    const x = pad + step * i;
                    const y = height - pad - (Math.max(0, Math.min(100, raw)) / 100) * (height - pad * 2);
                    if (!started) {
                        ctx.moveTo(x, y);
                        started = true;
                    } else {
                        ctx.lineTo(x, y);
                    }
                }
                ctx.stroke();
            }

            Connections {
                target: card
                function onSparklineValuesChanged() { sparklineCanvas.requestPaint(); }
                function onAccentColorChanged() { sparklineCanvas.requestPaint(); }
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4
            spacing: 2

            StyledText {
                text: card.title
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                spacing: Theme.spacingXS
                anchors.horizontalCenter: parent.horizontalCenter

                StyledText {
                    id: valueText
                    text: card.value
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                }

                StyledText {
                    text: card.unit
                    color: Theme.surfaceTextMedium
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.baseline: valueText.baseline
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }
    }

    component CpuDetails: Rectangle {
        property var cpuInfo: ({})

        height: 190
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                Layout.fillWidth: true

                MetricBox {
                    Layout.fillWidth: true
                    title: "Max"
                    value: root.formatFreq(cpuInfo.max_mhz || 0)
                }

                MetricBox {
                    Layout.fillWidth: true
                    title: "Average"
                    value: root.formatFreq(cpuInfo.avg_mhz || DgopService.cpuFrequency)
                }

                MetricBox {
                    Layout.fillWidth: true
                    title: "EPP"
                    value: cpuInfo.epp ? cpuInfo.epp.split("_").join(" ") : "--"
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingXS

                Repeater {
                    model: cpuInfo.cores || []

                    Rectangle {
                        width: 170
                        height: 30
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceVariant, 0.18)

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: "C" + modelData.index
                            color: Theme.surfaceTextMedium
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.formatFreq(modelData.mhz)
                            color: modelData.mhz >= 3000 ? "#ff6b6b" : (modelData.mhz >= 1800 ? "#ffd43b" : Theme.surfaceText)
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }

    component NetworkDetails: Rectangle {
        height: 190
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)

        Canvas {
            id: graph
            anchors.fill: parent
            anchors.margins: Theme.spacingM

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const rx = DgopService.networkHistory.rx || [];
                const tx = DgopService.networkHistory.tx || [];
                const all = rx.concat(tx);
                let maxValue = 1;
                for (let i = 0; i < all.length; i++)
                    maxValue = Math.max(maxValue, all[i] || 0);

                function draw(values, alpha, widthLine) {
                    if (!values || values.length < 2)
                        return;
                    ctx.beginPath();
                    for (let i = 0; i < values.length; i++) {
                        const x = (i / Math.max(1, values.length - 1)) * width;
                        const y = height - ((values[i] || 0) / maxValue) * height;
                        if (i === 0)
                            ctx.moveTo(x, y);
                        else
                            ctx.lineTo(x, y);
                    }
                    ctx.strokeStyle = Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, alpha);
                    ctx.lineWidth = widthLine;
                    ctx.stroke();
                }

                draw(rx, 0.95, 2.3);
                draw(tx, 0.45, 1.7);
            }

            Connections {
                target: DgopService
                function onNetworkRxRateChanged() { graph.requestPaint(); }
                function onNetworkTxRateChanged() { graph.requestPaint(); }
            }
        }
    }

    component MetricBox: Rectangle {
        property string title: ""
        property string value: ""

        height: 58
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceVariant, 0.16)

        Column {
            anchors.centerIn: parent
            spacing: 1

            StyledText {
                text: parent.title
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: parent.value
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
