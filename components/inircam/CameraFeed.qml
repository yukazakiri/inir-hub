import QtQuick
import QtMultimedia
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "Brands.js" as Brands

// One camera picture: the live stream, or what is known about it while it is not there.
// Nothing is fetched while `active` is false: a feed nobody looks at costs nothing.
Item {
    id: root

    required property var camera
    property string quality: "main"
    property bool active: true
    property bool muted: true
    property int retrySeconds: 15
    // Smallest delay; off buffers a little for unsteady networks.
    property bool lowLatency: true

    readonly property url streamUrl: root.camera ? Brands.streamUrl(root.camera, root.quality) : ""

    property string status: "idle"   // idle · connecting · live · error
    property string note: ""

    signal snapshotSaved(string path)
    signal snapshotFailed(string reason)

    function start() {
        if (!root.camera || root.streamUrl.toString() === "") {
            root.status = "idle"
            return
        }
        root.status = "connecting"
        player.source = root.streamUrl
        player.play()
    }

    function stop() {
        player.stop()
        player.source = ""
        root.status = "idle"
    }

    function takeSnapshot() {
        if (root.status !== "live") {
            root.snapshotFailed(Translation.tr("No picture to save"))
            return
        }
        const name = (root.camera.name || "camera").replace(/[^A-Za-z0-9 _-]/g, "_")
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")
        const path = `${Directories.picturesPath}/inircam-${name}-${stamp}.jpg`
        video.grabToImage(function(result) {
            if (result && result.saveToFile) {
                root.snapshotSaved(path)
            } else {
                root.snapshotFailed(Translation.tr("The picture could not be saved"))
            }
        })
    }

    implicitWidth: 320
    implicitHeight: 180

    onActiveChanged: if (root.active) root.start()
    else root.stop()
    onStreamUrlChanged: if (root.active) root.start()
    Component.onCompleted: if (root.active) root.start()
    Component.onDestruction: root.stop()

    MediaPlayer {
        id: player
        videoOutput: video
        audioOutput: audio
        playbackOptions.playbackIntent: root.lowLatency
            ? PlaybackOptions.PlaybackIntent.LowLatencyStreaming
            : PlaybackOptions.PlaybackIntent.Playback
        onMediaStatusChanged: {
            if (root.status === "idle") return
            if (mediaStatus === MediaPlayer.BufferedMedia) root.status = "connecting"
            else if (mediaStatus === MediaPlayer.PlayingMedia) root.status = "live"
            else if (mediaStatus === MediaPlayer.InvalidMedia || mediaStatus === MediaPlayer.EndOfMedia) {
                root.status = "error"
                root.note = Translation.tr("The camera stopped sending video")
                root.retry.restart()
            }
        }
        onErrorOccurred: function(error, errorString) {
            root.status = "error"
            root.note = Translation.tr("The camera could not be reached")
            root.retry.restart()
        }
    }

    AudioOutput {
        id: audio
        muted: root.muted
    }

    Timer {
        id: retry
        interval: Math.max(1, root.retrySeconds) * 1000
        repeat: true
        running: false
        onTriggered: if (root.active) root.start()
    }

    VideoOutput {
        id: video
        anchors.fill: parent
        visible: root.status === "live"
        fillMode: VideoOutput.PreserveAspectCrop
    }

    // The frame's own surface while the stream is still coming.
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainerHighest
        visible: root.status !== "live"
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 4
        visible: root.status !== "live"

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.status === "connecting" ? "sync" : "videocam_off"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurfaceVariant
            RotationAnimator on rotation {
                running: root.status === "connecting" && root.visible
                from: 0
                to: 360
                duration: 1100
                loops: Animation.Infinite
            }
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.status === "connecting" ? Translation.tr("Connecting…") : Translation.tr("No picture")
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.note !== ""
            text: root.note
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
        }
    }
}