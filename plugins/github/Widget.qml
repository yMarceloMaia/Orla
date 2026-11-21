import QtQuick

GithubTile {
    required property var host
    edge: host.edge
    ink: host.ink
    vertical: host.vertical
    leftEdge: host.leftEdge
    surface: host.background
    compact: host.cfg.githubCompact === true
    onToggleCompact: host.set("githubCompact", !compact)
    maxPanelWidth: host.screenWidth - 16
    maxPanelHeight: host.screenHeight - host.extent - 16
    data: host.service.githubData
    errorText: host.service.githubError
    busy: host.service.busy
    onRefresh: host.service.refresh()
    readonly property bool keepOpen: opened
}
