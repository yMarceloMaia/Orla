import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: service
    required property var host
    readonly property bool busy: githubFetch.running
    function refresh() { githubFetch.running = true; }
    property var githubData: ({})
    property var githubBaseline: null
    property double githubSince: 0
    function updateGithub(result) {
        const previous = githubBaseline;
        const watching = host.cfg.githubAlerts !== false;
        const current = result.alerts;
        if (watching && previous && previous.login === result.login) {
            for (const [url, pr] of Object.entries(current)) {
                const old = previous.alerts[url];
                if (!old && Date.parse(pr.created) < githubSince) continue;
                const added = pr.count - (old?.count || 0);
                const messages = [];
                if (added > 0) messages.push(added === 1 ? "New comment" : added + " new comments");
                if (pr.merge === "CONFLICTING" && old?.merge !== "CONFLICTING")
                    messages.push("Merge conflict");
                if (pr.merge === "UNKNOWN" && old) pr.merge = old.merge;
                if (messages.length)
                    Quickshell.execDetached(["notify-send", "--app-name=Orla", "--", pr.repo + " #" + pr.number, messages.join(" · ")]);
            }
        }
        githubBaseline = watching ? result : null;
        githubSince = Date.now();
        githubData = result;
    }
    readonly property bool githubWatching: host.cfg.githubAlerts !== false
    onGithubWatchingChanged: githubBaseline = null
    property string githubError: ""
    Process {
        id: githubFetch
        command: [host.helper, "github"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                const result = JSON.parse(text);
                service.githubError = result.error || "";
                if (!result.error) service.updateGithub(result);
            }
        }
    }
    Timer {
        interval: service.githubWatching ? 300000 : 900000
        running: true
        triggeredOnStart: true
        repeat: true
        onTriggered: githubFetch.running = true
    }
}
