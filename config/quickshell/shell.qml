import Quickshell
import Quickshell.Io
import QtQuick

Scope {
  id: root
  property string time

  Variants {
    model: Quickshell.screens

    // Default property of delegate
    PanelWindow {
      // screen from the screens list will be injected into this property
      property var modelData
      screen: modelData
      anchors {
        top: true
        left: true
        right: true
      }

      implicitHeight: 30

      Text {
        // ids are used to refer elsewhere in the file
        anchors.centerIn: parent
        text: root.time
      }
    }
  }

  Process {
    id: dateProc
    command: ["date"]
    running: true

    // SplitParser returns chunks of output after a delimiter
    stdout: SplitParser {
      // set clock.text to the stdout stream
      onRead: data => root.time = data
    }
  }

  Timer {
    interval: 1000 // update every second
    running: true
    repeat: true
    onTriggered: dateProc.running = true
  }
}

