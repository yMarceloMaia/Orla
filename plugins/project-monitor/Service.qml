import "../../projects"
import QtQuick

Item {
    id: service

    required property var host
    readonly property var docker: host.services["orla.docker"] || null

    onDockerChanged: ProjectHub.docker = docker
    Component.onCompleted: {
        ProjectHub.clients++;
        ProjectHub.docker = docker;
        ProjectHub.monitors++;
    }
    Component.onDestruction: {
        ProjectHub.clients--;
        ProjectHub.monitors--;
    }
}
