import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property string vpnText: "VPN …"

    preferredRepresentation: fullRepresentation
    toolTipMainText: "Duckybox VPN"
    toolTipSubText: root.vpnText

    fullRepresentation: PlasmaComponents.Label {
        id: label
        text: root.vpnText
        verticalAlignment: Text.AlignVCenter
        leftPadding: 6
        rightPadding: 6
        font.bold: true
        // Brand violet when connected, muted when offline.
        color: root.vpnText.indexOf("Disconnected") >= 0
               || root.vpnText.indexOf("offline") >= 0
                 ? "#9CA3AF"
                 : "#A78BFA"
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        interval: 5000

        onNewData: {
            var stdout = data["stdout"]
            if (typeof stdout === "string" && stdout.length > 0) {
                root.vpnText = stdout.trim()
            }
            disconnectSource(sourceName)
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource("/opt/duckybox/vpnpanel.sh")
    }
}
