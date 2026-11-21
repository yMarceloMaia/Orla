import QtQuick

Item {
    required property var host
    readonly property alias files: items
    ListModel { id: items }
    Component.onCompleted: {
        for (const file of host.memory.files || []) items.append(file);
    }
    Component.onDestruction: {
        const saved = [];
        for (let i = 0; i < items.count; i++)
            saved.push({uri: items.get(i).uri, filename: items.get(i).filename});
        host.memory.files = saved;
    }
}
