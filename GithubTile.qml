import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ToolButton {
    id: tile
    required property bool compact
    signal toggleCompact()
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: tile.toggleCompact()
    }
    required property int edge
    required property bool vertical
    required property bool leftEdge
    required property int maxPanelWidth
    required property int maxPanelHeight
    required property var data
    required property string errorText
    required property bool busy
    required property color ink
    required property color surface
    readonly property bool opened: popup.opened
    signal refresh()
    width: vertical || compact ? edge : edge + 105
    height: edge
    padding: 6
    Accessible.name: "Atividade do GitHub"
    onClicked: popup.open()
    background: Rectangle {
        radius: 10
        color: Qt.tint(tile.surface, Qt.alpha(tile.ink, tile.hovered ? 0.10 : 0.04))
        border.color: Qt.alpha(tile.ink, 0.16)
    }
    contentItem: RowLayout {
        spacing: 7
        Column {
            visible: !tile.vertical && !tile.compact
            Text { text: Number(tile.data.total || 0).toLocaleString(Qt.locale(), "f", 0); visible: tile.data.total !== undefined; font.bold: true; color: tile.ink }
            Text { text: tile.data.total !== undefined ? "neste ano" : "GitHub"; font.pixelSize: 10; color: tile.ink }
        }
        ContributionGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            weeks: tile.data.weeks || []
            ink: tile.ink
            limit: tile.vertical || tile.compact ? 7 : 18
        }
    }
    Popup {
        id: popup
        popupType: Popup.Window
        focus: true
        property bool reviews: true
        readonly property var group: reviews ? tile.data.reviews : tile.data.authored
        onAboutToShow: reviews = !!tile.data.reviews?.count || !tile.data.authored?.count
        onReviewsChanged: list.positionViewAtBeginning()
        padding: 18
        width: Math.min(470, tile.maxPanelWidth)
        height: Math.min(450, tile.maxPanelHeight)
        x: tile.vertical ? (tile.leftEdge ? tile.width : -width) : (tile.width - width) / 2
        y: tile.vertical ? (tile.height - height) / 2 : -height
        palette.buttonText: tile.ink
        palette.text: tile.ink
        background: Rectangle { radius: 12; color: tile.surface; border.color: Qt.alpha(tile.ink, 0.22) }
        contentItem: ColumnLayout {
            spacing: 8
            RowLayout {
                Label { Layout.fillWidth: true; text: "GitHub"; color: tile.ink; font.bold: true; font.pixelSize: 18 }
                RefreshButton { busy: tile.busy; ink: tile.ink; onClicked: tile.refresh() }
            }
            Label { visible: !!tile.errorText; Layout.fillWidth: true; wrapMode: Text.Wrap; text: tile.errorText; color: tile.ink }
            RowLayout {
                visible: tile.data.total !== undefined
                Label {
                    text: Number(tile.data.total ?? 0).toLocaleString(Qt.locale(), "f", 0)
                    color: tile.ink
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                }
                Label { text: "contribuições neste ano"; color: Qt.alpha(tile.ink, 0.74) }
            }
            ContributionGrid {
                visible: tile.data.total !== undefined
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(58, width * 7 / 53)
                weeks: tile.data.weeks || []; ink: tile.ink
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Repeater {
                    model: 2
                    delegate: ToolButton {
                        required property int index
                        readonly property bool selected: popup.reviews === (index === 0)
                        text: index === 0 ? "Revisões · " + (tile.data.reviews?.count ?? "…") : "Meus PRs · " + (tile.data.authored?.count ?? "…")
                        onClicked: popup.reviews = index === 0
                        padding: 4
                        font.weight: selected ? Font.DemiBold : Font.Normal
                        palette.buttonText: selected ? tile.ink : Qt.alpha(tile.ink, 0.7)
                        background: Rectangle {
                            color: parent.hovered || parent.visualFocus ? Qt.alpha(tile.ink, 0.07) : "transparent"
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 2
                                color: tile.ink; visible: parent.parent.selected
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: popup.group?.rows || []
                ScrollBar.vertical: ScrollBar {}
                delegate: ToolButton {
                    required property var modelData
                    width: list.width
                    onClicked: Qt.openUrlExternally(modelData.url)
                    id: row
                    ToolTip.visible: branches.truncated && (hovered || visualFocus)
                    ToolTip.text: branches.text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                    ToolTip.delay: 500
                    padding: 8
                    background: Rectangle {
                        color: row.hovered || row.visualFocus ? Qt.alpha(tile.ink, 0.08) : "transparent"
                        radius: 6
                    }
                    contentItem: ColumnLayout {
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.title; textFormat: Text.PlainText; elide: Text.ElideRight
                            color: tile.ink; font.weight: Font.DemiBold
                        }
                        Text {
                            id: branches
                            Layout.fillWidth: true
                            visible: !!row.modelData.head && !!row.modelData.base
                            text: visible ? row.modelData.head + " → " + row.modelData.base : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Qt.alpha(tile.ink, 0.82)
                            font.pixelSize: 12
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.repo + " #" + row.modelData.number
                                textFormat: Text.PlainText; elide: Text.ElideMiddle
                                color: Qt.alpha(tile.ink, 0.72); font.pixelSize: 11
                            }
                            Rectangle {
                                width: 7; height: 7; radius: 4
                                color: ({SUCCESS:"#39ad67", FAILURE:"#e96865", ERROR:"#e96865", PENDING:"#d3a546", EXPECTED:"#d3a546"})[row.modelData.checks] || Qt.alpha(tile.ink, 0.38)
                            }
                            Text {
                                text: ({SUCCESS:"Aprovado", FAILURE:"Falhou", ERROR:"Erro", PENDING:"Pendente", EXPECTED:"Aguardando", NONE:"Sem checks"})[row.modelData.checks] || "Sem checks"
                                color: tile.ink; font.pixelSize: 11
                            }
                        }
                    }
                }
                Label { anchors.centerIn: parent; visible: !list.count && tile.data.total !== undefined; text: popup.reviews ? "Nenhuma revisão solicitada" : "Nenhum PR aberto"; color: tile.ink }
            }
            ToolButton {
                visible: popup.group?.count > list.count
                text: "Ver todos no GitHub"
                onClicked: Qt.openUrlExternally("https://github.com/pulls?q=" + encodeURIComponent("is:pr is:open -user:minha-organizacao " + (popup.reviews ? "review-requested:@me" : "author:@me")))
            }
        }
    }
}
