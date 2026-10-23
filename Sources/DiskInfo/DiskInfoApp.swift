import SwiftUI
import AppKit

@main
struct DiskInfoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("DiskInfo — Mac 磁碟空間分析") {
            MainDiskView()
                .frame(minWidth: 1020, minHeight: 660)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
