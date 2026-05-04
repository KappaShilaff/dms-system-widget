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
    property var processExtraMetrics: ({})
    property string processExtraPidArg: ""
    property bool processExtraRefreshPending: false
    property var allProcessesWithExtra: []
    property var cpuFreqInfo: ({
        "avg_mhz": 0,
        "max_mhz": 0,
        "epp": "",
        "epp_available": [],
        "cores": []
    })
    Component.onCompleted: {
        DgopService.addRef(["processes", "cpu", "memory", "system"]);
        refreshCpuFrequencies();
    }

    Component.onDestruction: {
        DgopService.removeRef(["processes", "cpu", "memory", "system"]);
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

    function oneDecimalGb(kb) {
        return (Math.max(0, kb || 0) / (1024 * 1024)).toFixed(1);
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

    function localPath(url) {
        const value = String(url || "");
        return value.startsWith("file://") ? value.slice(7) : value;
    }

    function pluginPath() {
        const path = pluginService?.getPluginPath?.(pluginId || "dmsSystemPlugin") || "";
        return path.length > 0 ? path : localPath(Qt.resolvedUrl("."));
    }

    function cpuFrequencyHelperPath() {
        return pluginPath().replace(/\/$/, "") + "/scripts/cpu-frequencies.py";
    }

    function processExtraHelperPath() {
        return pluginPath().replace(/\/$/, "") + "/scripts/process-extra-metrics.py";
    }

    function mergeProcessExtra(processes) {
        const result = [];
        const metrics = processExtraMetrics || {};
        for (const proc of processes || []) {
            const extra = metrics[(proc.pid || 0).toString()] || {};
            result.push(Object.assign({}, proc, {
                "swapKB": extra.swapKB || proc.swapKB || 0,
                "gpuMemoryKB": extra.gpuMemoryKB || proc.gpuMemoryKB || 0,
                "gpuResidentKB": extra.gpuResidentKB || proc.gpuResidentKB || 0,
                "gpuSharedKB": extra.gpuSharedKB || proc.gpuSharedKB || 0
            }));
        }
        return result;
    }

    function refreshProcessExtraMetrics() {
        const processes = DgopService.allProcesses || [];
        allProcessesWithExtra = mergeProcessExtra(processes);

        const pids = processes.map(p => p.pid || 0).filter(pid => pid > 0).join(",");
        if (pids.length === 0)
            return;

        processExtraPidArg = pids;
        if (processExtraProcess.running) {
            processExtraRefreshPending = true;
            return;
        }
        processExtraProcess.running = true;
    }

    function gpuResidentKb() {
        let total = 0;
        const processes = allProcessesWithExtra || [];
        for (const proc of processes)
            total += proc.gpuResidentKB || proc.gpuMemoryKB || 0;
        return total;
    }

    function gpuMemoryKb() {
        let total = 0;
        const processes = allProcessesWithExtra || [];
        for (const proc of processes)
            total += proc.gpuMemoryKB || 0;
        return total;
    }

    function gpuSharedKb() {
        let total = 0;
        const processes = allProcessesWithExtra || [];
        for (const proc of processes)
            total += proc.gpuSharedKB || 0;
        return total;
    }

    function gpuProcesses(sortKey, ascending) {
        const processes = (allProcessesWithExtra || []).filter(proc => {
            return (proc.gpuMemoryKB || 0) > 0 || (proc.gpuSharedKB || 0) > 0 || (proc.gpuResidentKB || 0) > 0;
        });

        processes.sort((a, b) => {
            let result = 0;
            switch (sortKey) {
            case "name":
                result = (a.command || "").toLowerCase().localeCompare((b.command || "").toLowerCase());
                break;
            case "memory":
                result = (b.gpuMemoryKB || 0) - (a.gpuMemoryKB || 0);
                break;
            case "shared":
                result = (b.gpuSharedKB || 0) - (a.gpuSharedKB || 0);
                break;
            case "resident":
                result = (b.gpuResidentKB || 0) - (a.gpuResidentKB || 0);
                break;
            case "pid":
                result = (a.pid || 0) - (b.pid || 0);
                break;
            }
            return ascending ? -result : result;
        });

        return processes;
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
                        text: "DMS System"
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
                        value: root.oneDecimalGb(root.gpuResidentKb())
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

                GpuDetails {
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
                        processes: root.allProcessesWithExtra
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
        command: ["python3", root.cpuFrequencyHelperPath()]
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

    Process {
        id: processExtraProcess
        command: ["python3", root.processExtraHelperPath(), root.processExtraPidArg]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("DmsSystemPlugin: process extra metrics failed with exit code", exitCode);
            }
            if (root.processExtraRefreshPending) {
                root.processExtraRefreshPending = false;
                processExtraProcess.running = true;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    try {
                        root.processExtraMetrics = JSON.parse(text.trim());
                        root.allProcessesWithExtra = root.mergeProcessExtra(DgopService.allProcesses || []);
                    } catch (e) {
                        console.warn("DmsSystemPlugin: failed to parse process extra metrics", e);
                    }
                }
            }
        }
    }

    Connections {
        target: DgopService
        function onAllProcessesChanged() {
            root.refreshProcessExtraMetrics();
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

        implicitHeight: detailsColumn.implicitHeight + Theme.spacingM * 2
        Layout.preferredHeight: implicitHeight
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)

        ColumnLayout {
            id: detailsColumn

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
                            text: root.formatFreq(modelData.current_mhz || modelData.mhz || 0)
                            color: (modelData.current_mhz || modelData.mhz || 0) >= 3000 ? "#ff6b6b" : ((modelData.current_mhz || modelData.mhz || 0) >= 1800 ? "#ffd43b" : Theme.surfaceText)
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }

    component GpuDetails: Rectangle {
        id: gpuDetails

        property string sortKey: "resident"
        property bool sortAscending: false

        function changeSort(key) {
            if (sortKey === key) {
                sortAscending = !sortAscending;
                return;
            }
            sortKey = key;
            sortAscending = key === "name" || key === "pid";
        }

        height: 260
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
                    title: "Memory"
                    value: root.formatMem(root.gpuMemoryKb())
                }

                MetricBox {
                    Layout.fillWidth: true
                    title: "Shared"
                    value: root.formatMem(root.gpuSharedKb())
                }

                MetricBox {
                    Layout.fillWidth: true
                    title: "Resident"
                    value: root.formatMem(root.gpuResidentKb())
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceVariant, 0.10)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        Layout.leftMargin: Theme.spacingS
                        Layout.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        GpuHeader {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 190
                            text: "Name"
                            sortKey: "name"
                            currentSort: gpuDetails.sortKey
                            sortAscending: gpuDetails.sortAscending
                            alignment: Text.AlignLeft
                            onClicked: gpuDetails.changeSort(sortKey)
                        }

                        GpuHeader { text: "Memory"; sortKey: "memory"; currentSort: gpuDetails.sortKey; sortAscending: gpuDetails.sortAscending; onClicked: gpuDetails.changeSort(sortKey) }
                        GpuHeader { text: "Shared"; sortKey: "shared"; currentSort: gpuDetails.sortKey; sortAscending: gpuDetails.sortAscending; onClicked: gpuDetails.changeSort(sortKey) }
                        GpuHeader { text: "Resident"; sortKey: "resident"; currentSort: gpuDetails.sortKey; sortAscending: gpuDetails.sortAscending; onClicked: gpuDetails.changeSort(sortKey) }
                        GpuHeader { text: "PID"; sortKey: "pid"; currentSort: gpuDetails.sortKey; sortAscending: gpuDetails.sortAscending; onClicked: gpuDetails.changeSort(sortKey) }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.gpuProcesses(gpuDetails.sortKey, gpuDetails.sortAscending)

                        delegate: RowLayout {
                            required property var modelData

                            width: ListView.view.width
                            height: 36
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 190
                                Layout.leftMargin: Theme.spacingS
                                text: modelData.command || "process"
                                elide: Text.ElideRight
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            GpuValue { text: root.formatMem(modelData.gpuMemoryKB || 0) }
                            GpuValue { text: root.formatMem(modelData.gpuSharedKB || 0) }
                            GpuValue { text: root.formatMem(modelData.gpuResidentKB || 0) }
                            GpuValue { text: (modelData.pid || 0).toString() }
                        }
                    }
                }
            }
        }
    }

    component GpuHeader: Item {
        property string text: ""
        property string sortKey: ""
        property string currentSort: ""
        property bool sortAscending: false
        property int alignment: Text.AlignHCenter

        signal clicked

        Layout.preferredWidth: 112
        Layout.preferredHeight: 34

        StyledText {
            anchors.fill: parent
            text: parent.text + (parent.currentSort === parent.sortKey ? (parent.sortAscending ? " ↑" : " ↓") : "")
            color: parent.currentSort === parent.sortKey ? Theme.primary : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: parent.alignment
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component GpuValue: StyledText {
        Layout.preferredWidth: 112
        horizontalAlignment: Text.AlignHCenter
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
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
                text: title
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: value
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
