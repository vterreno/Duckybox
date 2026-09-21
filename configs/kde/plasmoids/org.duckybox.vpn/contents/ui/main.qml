import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support 2.0 as Plasma5Support

Item {
    id: root

    property string vpnText: "VPN …"

    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation
    Plasmoid.toolTipMainText: "Duckybox VPN"
    Plasmoid.toolTipSubText: root.vpnText

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
