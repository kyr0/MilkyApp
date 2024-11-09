import SwiftUI

let kAppSubsystem = "de.aronhomberg.Milky"

@main
struct MilkyApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        print("Started")
        setMainThreadHighPriority();
    }
    
    func setMainThreadHighPriority() {
        let qosClass: qos_class_t = QOS_CLASS_USER_INTERACTIVE  // High QoS for UI/foreground tasks
        let priority: Int32 = 63  // relative prio
        pthread_set_qos_class_self_np(qosClass, priority)
    }
     
    var body: some Scene {
        WindowGroup {
            RootView()
                .fixedSize()
               
        }
        .windowResizability(.contentSize) // Ensures the window fits content size
    }
}


// make sure the App doesn't quit when the config window is closed
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Prevents the app from quitting when the last window is closed
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.delegate = self
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.orderOut(nil) // Hide the window instead of closing the app
        }
    }
}

