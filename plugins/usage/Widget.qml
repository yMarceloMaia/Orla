import QtQuick

UsageTile {
    required property var host
    edge: host.edge
    preferredEdge: host.preferredEdge ?? host.edge
    ink: host.ink
    vertical: host.vertical
    condensed: host.compact === true
    leftEdge: host.leftEdge
    surface: host.background
    profile: host.cfg.usageCompact === true ? "Claude" : (host.cfg.usageCompact || "all")
    summaryPeriod: host.preference("summaryPeriod", "Semanal")
    onSelectSummaryPeriod: period => host.savePreference("summaryPeriod", period)
    accounts: host.service.planUsage
    busy: host.service.busy
    onRefresh: host.service.refresh()
    onSelectProfile: name => host.set("usageCompact", name)
    readonly property bool keepOpen: opened
    onShowAccountHintChanged: host.tip(this, showAccountHint)
}
