import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: overview

    required property var windows
    required property int workspace
    required property string activeAddress
    required property color surface
    required property color ink
    required property color accent
    signal selected(string address)
    signal dismissed

    readonly property color muted: Qt.alpha(ink, 0.68)
    readonly property color line: Qt.alpha(ink, 0.13)
    readonly property color tileSurface: Qt.tint(surface, Qt.alpha(ink, 0.047))
    readonly property color selectedSurface: Qt.tint(tileSurface, Qt.alpha(accent, 0.10))
    readonly property int columns: Math.max(1, Math.min(4, windows.length, Math.floor((screen.width - 60) / 252)))
    readonly property int cardWidth: Math.min(314, Math.floor((screen.width - 60) / columns))
    readonly property int cardHeight: Math.min(190, Math.round(cardWidth * 0.58)) + 85
    readonly property int rows: Math.ceil(windows.length / columns)
    readonly property var selectedWindow: windows[grid.currentIndex]
    implicitWidth: Math.min(screen.width - 24, Math.max(390, columns * cardWidth + 36))
    implicitHeight: Math.min(screen.height - 32, Math.ceil(contentLayout.implicitHeight + navigation.anchors.topMargin + navigation.anchors.bottomMargin))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "orla-window-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    function choose(index) {
        const window = windows[index];
        if (window)
            selected(window.address);
    }

    component Caption: Label {
        color: overview.ink
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }

    component KeyCap: Rectangle {
        id: cap
        required property string text
        color: Qt.alpha(overview.ink, 0.048)
        border.color: overview.line
        radius: 5
        implicitWidth: keyLabel.implicitWidth + 12
        implicitHeight: 22
        Caption {
            id: keyLabel
            anchors.centerIn: parent
            text: cap.text
            color: overview.muted
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 19
        color: overview.surface
        border.color: overview.line
    }

    FocusScope {
        id: navigation
        anchors.fill: parent
        anchors.margins: 18
        focus: true
        Component.onCompleted: {
            const index = overview.windows.findIndex(w => w.address === overview.activeAddress);
            grid.currentIndex = index < 0 ? 0 : index;
            forceActiveFocus();
        }
        Keys.priority: Keys.BeforeItem
        Keys.onEscapePressed: overview.dismissed()
        Keys.onReturnPressed: overview.choose(grid.currentIndex)
        Keys.onEnterPressed: overview.choose(grid.currentIndex)
        Keys.onLeftPressed: grid.moveCurrentIndexLeft()
        Keys.onRightPressed: grid.moveCurrentIndexRight()
        Keys.onUpPressed: grid.moveCurrentIndexUp()
        Keys.onDownPressed: grid.moveCurrentIndexDown()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                grid.currentIndex = event.key === Qt.Key_Home ? 0 : grid.count - 1;
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 3
                    Caption {
                        text: "Workspace " + overview.workspace
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                    Caption {
                        text: overview.windows.length === 1 ? "1 window" : overview.windows.length + " windows"
                        color: overview.muted
                        font.pixelSize: 12
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                ToolButton {
                    id: closeButton
                    implicitWidth: 32
                    implicitHeight: 32
                    Accessible.name: "Close window overview"
                    onClicked: overview.dismissed()
                    contentItem: Caption {
                        text: "×"
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: Qt.alpha(overview.ink, closeButton.hovered ? 0.12 : 0.05)
                        border.color: closeButton.visualFocus ? overview.accent : overview.line
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: overview.line
            }
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: overview.rows ? overview.rows * cellHeight : 92
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: overview.rows ? overview.columns * overview.cardWidth : Infinity
                cellWidth: overview.cardWidth
                cellHeight: overview.cardHeight
                model: overview.windows
                clip: true
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height + 0.5
                ScrollBar.vertical: ScrollBar {
                    policy: grid.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }
                delegate: ToolButton {
                    id: card
                    required property int index
                    required property var modelData
                    readonly property var app: DesktopEntries.heuristicLookup(modelData.initialClass || modelData.class)
                    readonly property bool current: GridView.isCurrentItem
                    readonly property bool focusedWindow: !modelData.parked && modelData.address === overview.activeAddress
                    readonly property string title: modelData.title || app?.name || modelData.class || "Window"
                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    padding: 8
                    hoverEnabled: true
                    Accessible.name: title + (modelData.parked ? " · Minimized" : "")
                    onClicked: overview.choose(index)
                    background: Rectangle {
                        radius: 12
                        color: card.current ? overview.selectedSurface : card.hovered ? Qt.tint(overview.tileSurface, Qt.alpha(overview.ink, 0.045)) : overview.tileSurface
                        border.color: card.current || card.visualFocus ? overview.accent : overview.line
                        border.width: card.current ? 2 : 1
                    }
                    contentItem: ColumnLayout {
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Image {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                sourceSize: Qt.size(36, 36)
                                fillMode: Image.PreserveAspectFit
                                source: Quickshell.iconPath(card.app?.icon || "application-x-executable", true)
                            }
                            Caption {
                                Layout.fillWidth: true
                                text: card.app?.name || card.modelData.class || "Window"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                visible: card.modelData.parked || card.focusedWindow
                                implicitWidth: stateLabel.implicitWidth + 12
                                implicitHeight: 21
                                radius: 6
                                color: Qt.alpha(card.focusedWindow ? overview.accent : overview.ink, card.focusedWindow ? 0.14 : 0.07)
                                Caption {
                                    id: stateLabel
                                    anchors.centerIn: parent
                                    text: card.modelData.parked ? "Minimized" : "Focused"
                                    color: card.focusedWindow ? overview.ink : overview.muted
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }
                        }
                        WindowThumb {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Qt.tint(overview.surface, Qt.alpha(overview.ink, 0.085))
                            client: card.modelData
                        }
                        Caption {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            text: card.title
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }
                }
                Caption {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: "No windows in this workspace"
                    color: overview.muted
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: overview.line
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                KeyCap {
                    visible: grid.count > 0
                    text: "← ↑ ↓ →"
                }
                Caption {
                    visible: grid.count > 0
                    text: "Navigate"
                    color: overview.muted
                    font.pixelSize: 11
                }
                Item {
                    Layout.fillWidth: true
                }
                KeyCap {
                    visible: grid.count > 0
                    text: "Enter"
                }
                Caption {
                    visible: grid.count > 0
                    text: overview.selectedWindow?.parked ? "Restore" : "Focus"
                    color: overview.ink
                    font.pixelSize: 11
                    Layout.rightMargin: 8
                }
                KeyCap {
                    text: "Esc"
                }
                Caption {
                    text: "Close"
                    color: overview.muted
                    font.pixelSize: 11
                }
            }
        }
    }
}
