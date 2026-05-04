import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property string searchText: ""
    property string expandedPid: ""
    property var contextMenu: null
    property string processFilter: "all" // "all", "user", "system"
    property var processes: []

    property int selectedIndex: -1
    property bool keyboardNavigationActive: false
    property int forceRefreshCount: 0
    property real pendingScrollY: -1
    property int pendingScrollAttempts: 0
    property bool restoringScroll: false
    property bool allowScrollSave: false
    property real initialScrollY: SessionData.processListScrollY || 0
    property bool listReady: initialScrollY <= 0

    readonly property bool pauseUpdates: (contextMenu?.visible ?? false) || expandedPid.length > 0
    readonly property bool shouldUpdate: !pauseUpdates || forceRefreshCount > 0
    property var cachedProcesses: []

    signal openContextMenuRequested(int index, real x, real y, bool fromKeyboard)

    onFilteredProcessesChanged: {
        if (!shouldUpdate)
            return;
        cachedProcesses = filteredProcesses;
        modelSettledTimer.restart();
        if (forceRefreshCount > 0)
            forceRefreshCount--;
    }

    onShouldUpdateChanged: {
        if (shouldUpdate) {
            cachedProcesses = filteredProcesses;
            modelSettledTimer.restart();
        }
    }

    readonly property var filteredProcesses: {
        if (!processes || processes.length === 0)
            return [];

        let procs = processes.slice();

        if (processFilter === "user") {
            procs = procs.filter(p => p.username === UserInfoService.username);
        } else if (processFilter === "system") {
            procs = procs.filter(p => p.username !== UserInfoService.username);
        }

        if (searchText.length > 0) {
            const search = searchText.toLowerCase();
            procs = procs.filter(p => {
                const cmd = (p.command || "").toLowerCase();
                const pid = p.pid.toString();
                return cmd.includes(search) || pid.includes(search);
            });
        }

        const asc = DgopService.sortAscending;
        procs.sort((a, b) => {
            let valueA, valueB, result;
            switch (DgopService.currentSort) {
            case "cpu":
                valueA = a.cpu || 0;
                valueB = b.cpu || 0;
                result = valueB - valueA;
                break;
            case "memory":
                valueA = a.memoryKB || 0;
                valueB = b.memoryKB || 0;
                result = valueB - valueA;
                break;
            case "swap":
                valueA = a.swapKB || 0;
                valueB = b.swapKB || 0;
                result = valueB - valueA;
                break;
            case "gpu":
                valueA = a.gpuMemoryKB || 0;
                valueB = b.gpuMemoryKB || 0;
                result = valueB - valueA;
                break;
            case "name":
                valueA = (a.command || "").toLowerCase();
                valueB = (b.command || "").toLowerCase();
                result = valueA.localeCompare(valueB);
                break;
            case "pid":
                valueA = a.pid || 0;
                valueB = b.pid || 0;
                result = valueA - valueB;
                break;
            default:
                return 0;
            }
            return asc ? -result : result;
        });

        return procs;
    }

    function selectNext() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = Math.min(selectedIndex + 1, cachedProcesses.length - 1);
        ensureVisible();
    }

    function selectPrevious() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        if (selectedIndex <= 0) {
            selectedIndex = -1;
            keyboardNavigationActive = false;
            return;
        }
        selectedIndex = selectedIndex - 1;
        ensureVisible();
    }

    function selectFirst() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = 0;
        ensureVisible();
    }

    function selectLast() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = cachedProcesses.length - 1;
        ensureVisible();
    }

    function toggleExpand() {
        if (selectedIndex < 0 || selectedIndex >= cachedProcesses.length)
            return;
        const process = cachedProcesses[selectedIndex];
        const pidStr = (process?.pid ?? -1).toString();
        expandedPid = (expandedPid === pidStr) ? "" : pidStr;
    }

    function openContextMenu() {
        if (selectedIndex < 0 || selectedIndex >= cachedProcesses.length)
            return;
        const delegate = processListView.itemAtIndex(selectedIndex);
        if (!delegate)
            return;
        const process = cachedProcesses[selectedIndex];
        if (!process || !contextMenu)
            return;
        contextMenu.processData = process;
        const itemPos = delegate.mapToItem(contextMenu.parent, delegate.width / 2, delegate.height / 2);
        contextMenu.parentFocusItem = root;
        contextMenu.show(itemPos.x, itemPos.y, true);
    }

    function reset() {
        selectedIndex = -1;
        keyboardNavigationActive = false;
        expandedPid = "";
    }

    function currentScrollY() {
        return processListView.contentY;
    }

    function restoreScrollY(contentY) {
        allowScrollSave = false;
        if (listReady && Math.abs(processListView.contentY - contentY) < 1) {
            processListView.savedY = contentY;
            enableScrollSaveTimer.restart();
            return;
        }
        initialScrollY = contentY;
        processListView.savedY = contentY;
        processListView.contentY = contentY;
        listReady = contentY <= 0;
        pendingScrollY = contentY;
        pendingScrollAttempts = 12;
        scrollRestoreTimer.restart();
    }

    function applyPendingScrollY() {
        if (pendingScrollY < 0)
            return;

        const minY = processListView.originY;
        const maxY = Math.max(minY, processListView.contentHeight - processListView.height);
        if (maxY <= minY && pendingScrollAttempts > 0) {
            pendingScrollAttempts--;
            scrollRestoreTimer.restart();
            return;
        }

        restoringScroll = true;
        const targetY = Math.max(minY, Math.min(pendingScrollY, maxY));
        processListView.savedY = targetY;
        processListView.contentY = targetY;
        Qt.callLater(() => {
            processListView.savedY = targetY;
            processListView.contentY = targetY;
            listReady = true;
            restoringScroll = false;
            enableScrollSaveTimer.restart();
        });
        pendingScrollY = -1;
        pendingScrollAttempts = 0;
    }

    function saveCurrentScrollY(force) {
        if ((!force && !allowScrollSave) || restoringScroll || searchText.length > 0)
            return;
        SessionData.processListScrollY = processListView.contentY;
        processListView.savedY = processListView.contentY;
    }

    function resetScrollToTop() {
        const topY = processListView.originY;
        initialScrollY = topY;
        pendingScrollY = -1;
        pendingScrollAttempts = 0;
        listReady = true;
        processListView.savedY = topY;
        processListView.contentY = topY;
        SessionData.processListScrollY = topY;
        enableScrollSaveTimer.restart();
    }

    function clampScrollToBounds() {
        if (cachedProcesses.length === 0)
            return;

        listReady = true;
        const minY = processListView.originY;
        const maxY = Math.max(minY, processListView.contentHeight - processListView.height);
        if (processListView.contentY < minY || processListView.contentY > maxY) {
            const clampedY = Math.max(minY, Math.min(processListView.contentY, maxY));
            processListView.savedY = clampedY;
            processListView.contentY = clampedY;
            if (allowScrollSave && searchText.length === 0)
                SessionData.processListScrollY = clampedY;
        }
    }

    function changeSort(sortKey) {
        resetScrollToTop();
        DgopService.toggleSort(sortKey);
        Qt.callLater(() => resetScrollToTop());
    }

    function forceRefresh(count) {
        forceRefreshCount = count || 3;
    }

    function ensureVisible() {
        if (selectedIndex < 0)
            return;
        processListView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Down:
            selectNext();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            selectPrevious();
            event.accepted = true;
            return;
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                selectNext();
                event.accepted = true;
            }
            return;
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                selectPrevious();
                event.accepted = true;
            }
            return;
        case Qt.Key_Home:
            selectFirst();
            event.accepted = true;
            return;
        case Qt.Key_End:
            selectLast();
            event.accepted = true;
            return;
        case Qt.Key_Space:
            if (keyboardNavigationActive) {
                toggleExpand();
                event.accepted = true;
            }
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (keyboardNavigationActive) {
                toggleExpand();
                event.accepted = true;
            }
            return;
        case Qt.Key_Menu:
        case Qt.Key_F10:
            if (keyboardNavigationActive && selectedIndex >= 0) {
                openContextMenu();
                event.accepted = true;
            }
            return;
        }
    }

    Component.onCompleted: {
        DgopService.addRef(["processes", "cpu", "memory", "system"]);
        cachedProcesses = filteredProcesses;
        modelSettledTimer.restart();
    }

    Component.onDestruction: {
        DgopService.removeRef(["processes", "cpu", "memory", "system"]);
    }

    Timer {
        id: scrollRestoreTimer
        interval: 100
        repeat: false
        onTriggered: root.applyPendingScrollY()
    }

    Timer {
        id: enableScrollSaveTimer
        interval: 500
        repeat: false
        onTriggered: root.allowScrollSave = true
    }

    Timer {
        id: modelSettledTimer
        interval: 0
        repeat: false
        onTriggered: root.clampScrollToBounds()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingS
                anchors.rightMargin: Theme.spacingS
                spacing: 0

                SortableHeader {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 200
                    text: I18n.tr("Name")
                    sortKey: "name"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: root.changeSort("name")
                    alignment: Text.AlignLeft
                }

                SortableHeader {
                    Layout.preferredWidth: 80
                    text: "CPU"
                    sortKey: "cpu"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: root.changeSort("cpu")
                }

                SortableHeader {
                    Layout.preferredWidth: 90
                    text: "RAM"
                    sortKey: "memory"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: root.changeSort("memory")
                }

                SortableHeader {
                    Layout.preferredWidth: 90
                    text: "Swap"
                    sortKey: "swap"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: root.changeSort("swap")
                }

                SortableHeader {
                    Layout.preferredWidth: 90
                    text: "GPU"
                    sortKey: "gpu"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: root.changeSort("gpu")
                }

                SortableHeader {
                    Layout.preferredWidth: 70
                    text: "PID"
                    sortKey: "pid"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: root.changeSort("pid")
                }

                Item {
                    Layout.preferredWidth: 40
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.outlineLight
        }

        DankListView {
            id: processListView

            Layout.fillWidth: true
            Layout.fillHeight: true
            savedY: root.initialScrollY
            opacity: root.listReady ? 1 : 0
            enabled: root.listReady
            clip: true
            spacing: 2

            Component.onCompleted: {
                savedY = root.initialScrollY;
                contentY = root.initialScrollY;
            }

            add: root.searchText.length > 0 ? ListViewTransitions.add : null
            remove: root.searchText.length > 0 ? ListViewTransitions.remove : null
            displaced: root.searchText.length > 0 ? ListViewTransitions.displaced : null
            move: root.searchText.length > 0 ? ListViewTransitions.move : null

            onMovementEnded: root.saveCurrentScrollY()
            onFlickEnded: root.saveCurrentScrollY()
            onContentYChanged: root.saveCurrentScrollY()
            onContentHeightChanged: root.clampScrollToBounds()
            onHeightChanged: root.clampScrollToBounds()

            model: ScriptModel {
                values: root.cachedProcesses
                objectProp: "pid"
            }

            delegate: ProcessItem {
                required property var modelData
                required property int index

                width: processListView.width
                process: modelData
                isExpanded: root.expandedPid === (modelData?.pid ?? -1).toString()
                isSelected: root.keyboardNavigationActive && root.selectedIndex === index
                contextMenu: root.contextMenu
                onToggleExpand: {
                    const pidStr = (modelData?.pid ?? -1).toString();
                    root.expandedPid = (root.expandedPid === pidStr) ? "" : pidStr;
                }
                onClicked: {
                    root.keyboardNavigationActive = true;
                    root.selectedIndex = index;
                }
                onContextMenuRequested: (mouseX, mouseY) => {
                    if (root.contextMenu) {
                        root.contextMenu.processData = modelData;
                        root.contextMenu.parentFocusItem = root;
                        const globalPos = mapToItem(root.contextMenu.parent, mouseX, mouseY);
                        root.contextMenu.show(globalPos.x, globalPos.y, false);
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 300
                height: 100
                radius: Theme.cornerRadius
                color: "transparent"
                visible: root.cachedProcesses.length === 0

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingM

                    DankIcon {
                        name: root.searchText.length > 0 ? "search_off" : "hourglass_empty"
                        size: 32
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: I18n.tr("No matching processes", "empty state in process list")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.searchText.length > 0
                    }
                }
            }
        }
    }

    component SortableHeader: Item {
        id: headerItem

        property string text: ""
        property string sortKey: ""
        property string currentSort: ""
        property bool sortAscending: false
        property int alignment: Text.AlignHCenter

        signal clicked

        readonly property bool isActive: sortKey === currentSort

        height: 36

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Theme.cornerRadius
            color: headerItem.isActive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (headerMouseArea.containsMouse ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06) : "transparent")

            Behavior on color {
                ColorAnimation {
                    duration: Theme.shortDuration
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            spacing: 4

            Item {
                Layout.fillWidth: headerItem.alignment === Text.AlignLeft
                visible: headerItem.alignment !== Text.AlignLeft
            }

            StyledText {
                text: headerItem.text
                font.pixelSize: Theme.fontSizeSmall
                font.family: SettingsData.monoFontFamily
                font.weight: Font.Medium
                color: headerItem.isActive ? Theme.primary : Theme.surfaceText
                opacity: headerItem.isActive ? 1 : 0.8
            }

            DankIcon {
                name: headerItem.sortAscending ? "arrow_upward" : "arrow_downward"
                size: Theme.fontSizeSmall
                color: Theme.primary
                visible: headerItem.isActive
            }

            Item {
                Layout.fillWidth: headerItem.alignment !== Text.AlignLeft
                visible: headerItem.alignment === Text.AlignLeft
            }
        }

        MouseArea {
            id: headerMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: headerItem.clicked()
        }
    }

    component ProcessItem: Rectangle {
        id: processItemRoot

        property var process: null
        property bool isExpanded: false
        property bool isSelected: false
        property var contextMenu: null

        signal toggleExpand
        signal clicked
        signal contextMenuRequested(real mouseX, real mouseY)

        readonly property int processPid: process?.pid ?? 0
        readonly property real processCpu: process?.cpu ?? 0
        readonly property int processMemKB: process?.memoryKB ?? 0
        readonly property int processSwapKB: process?.swapKB ?? 0
        readonly property int processGpuKB: process?.gpuMemoryKB ?? 0
        readonly property int processGpuSharedKB: process?.gpuSharedKB ?? 0
        readonly property int processGpuResidentKB: process?.gpuResidentKB ?? 0
        readonly property string processCmd: process?.command ?? ""
        readonly property string processFullCmd: process?.fullCommand ?? processCmd

        height: isExpanded ? (44 + expandedRect.height + Theme.spacingXS) : 44
        radius: Theme.cornerRadius
        color: {
            if (isSelected)
                return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15);
            return processMouseArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06) : "transparent";
        }
        border.color: {
            if (isSelected)
                return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3);
            return processMouseArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent";
        }
        border.width: 1
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Theme.shortDuration
            }
        }

        MouseArea {
            id: processMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    processItemRoot.contextMenuRequested(mouse.x, mouse.y);
                    return;
                }
                processItemRoot.clicked();
                processItemRoot.toggleExpand();
            }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width
                height: 44

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 200
                        height: parent.height

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: DgopService.getProcessIcon(processItemRoot.processCmd)
                                size: Theme.iconSize - 4
                                color: {
                                    if (processItemRoot.processCpu > 80)
                                        return Theme.error;
                                    if (processItemRoot.processCpu > 50)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                                opacity: 0.8
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: processItemRoot.processCmd
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 280)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 80
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 70
                            height: 24
                            radius: Theme.cornerRadius
                            color: {
                                if (processItemRoot.processCpu > 80)
                                    return Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15);
                                if (processItemRoot.processCpu > 50)
                                    return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.12);
                                return Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: DgopService.formatCpuUsage(processItemRoot.processCpu)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Bold
                                color: {
                                    if (processItemRoot.processCpu > 80)
                                        return Theme.error;
                                    if (processItemRoot.processCpu > 50)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 90
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 76
                            height: 24
                            radius: Theme.cornerRadius
                            color: {
                                if (processItemRoot.processMemKB > 2 * 1024 * 1024)
                                    return Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15);
                                if (processItemRoot.processMemKB > 1024 * 1024)
                                    return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.12);
                                return Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: DgopService.formatMemoryUsage(processItemRoot.processMemKB)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Bold
                                color: {
                                    if (processItemRoot.processMemKB > 2 * 1024 * 1024)
                                        return Theme.error;
                                    if (processItemRoot.processMemKB > 1024 * 1024)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 90
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 76
                            height: 24
                            radius: Theme.cornerRadius
                            color: {
                                if (processItemRoot.processSwapKB > 1024 * 1024)
                                    return Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15);
                                if (processItemRoot.processSwapKB > 256 * 1024)
                                    return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.12);
                                return Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: DgopService.formatMemoryUsage(processItemRoot.processSwapKB)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Bold
                                color: {
                                    if (processItemRoot.processSwapKB > 1024 * 1024)
                                        return Theme.error;
                                    if (processItemRoot.processSwapKB > 256 * 1024)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 90
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 76
                            height: 24
                            radius: Theme.cornerRadius
                            color: {
                                if (processItemRoot.processGpuKB > 2 * 1024 * 1024)
                                    return Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15);
                                if (processItemRoot.processGpuKB > 1024 * 1024)
                                    return Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.12);
                                return Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: DgopService.formatMemoryUsage(processItemRoot.processGpuKB)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Bold
                                color: {
                                    if (processItemRoot.processGpuKB > 2 * 1024 * 1024)
                                        return Theme.error;
                                    if (processItemRoot.processGpuKB > 1024 * 1024)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 70
                        height: parent.height

                        StyledText {
                            anchors.centerIn: parent
                            text: processItemRoot.processPid > 0 ? processItemRoot.processPid.toString() : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: SettingsData.monoFontFamily
                            color: Theme.surfaceVariantText
                        }
                    }

                    Item {
                        Layout.preferredWidth: 40
                        height: parent.height

                        DankIcon {
                            anchors.centerIn: parent
                            name: processItemRoot.isExpanded ? "expand_less" : "expand_more"
                            size: Theme.iconSize - 4
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }

            Rectangle {
                id: expandedRect
                width: parent.width - Theme.spacingM * 2
                height: processItemRoot.isExpanded ? (expandedContent.implicitHeight + Theme.spacingS * 2) : 0
                anchors.horizontalCenter: parent.horizontalCenter
                radius: Theme.cornerRadius - 2
                color: Qt.rgba(Theme.surfaceContainerHigh.r, Theme.surfaceContainerHigh.g, Theme.surfaceContainerHigh.b, 0.6)
                clip: true
                visible: processItemRoot.isExpanded

                Behavior on height {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Column {
                    id: expandedContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingXS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            id: cmdLabel
                            text: I18n.tr("Full Command:", "process detail label")
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.weight: Font.Bold
                            color: Theme.surfaceVariantText
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            id: cmdText
                            text: processItemRoot.processFullCmd
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.family: SettingsData.monoFontFamily
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            elide: Text.ElideMiddle
                        }

                        Rectangle {
                            id: copyBtn
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            radius: Theme.cornerRadius - 2
                            color: copyMouseArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"

                            DankIcon {
                                anchors.centerIn: parent
                                name: "content_copy"
                                size: 14
                                color: copyMouseArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                            }

                            MouseArea {
                                id: copyMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["dms", "cl", "copy", processItemRoot.processFullCmd]);
                                }
                            }
                        }

                        Rectangle {
                            id: killBtn
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            radius: Theme.cornerRadius - 2
                            color: killMouseArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.22) : Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                DankIcon {
                                    name: "close"
                                    size: 13
                                    color: Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "Kill"
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    font.weight: Font.Medium
                                    color: Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: killMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (processItemRoot.processPid > 0)
                                        Quickshell.execDetached(["kill", processItemRoot.processPid.toString()]);
                                }
                            }
                        }
                    }

                    Row {
                        spacing: Theme.spacingL

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "PPID:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: (processItemRoot.process?.ppid ?? 0) > 0 ? processItemRoot.process.ppid.toString() : "--"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Mem:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: (processItemRoot.process?.memoryPercent ?? 0).toFixed(1) + "%"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Swap:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: DgopService.formatMemoryUsage(processItemRoot.processSwapKB)
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "GPU mem:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: DgopService.formatMemoryUsage(processItemRoot.processGpuKB)
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "GPU shared:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: DgopService.formatMemoryUsage(processItemRoot.processGpuSharedKB)
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "GPU resident:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: DgopService.formatMemoryUsage(processItemRoot.processGpuResidentKB)
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }
        }
    }
}
