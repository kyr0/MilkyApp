import SwiftUI

let kAppSubsystem = "de.aronhomberg.Milky"

@main
struct MilkyApp: App {
    
    /*
    init() {
        setMainThreadHighPriority();
    }
    
    func setMainThreadHighPriority() {
        let qosClass: qos_class_t = QOS_CLASS_USER_INTERACTIVE  // High QoS for UI/foreground tasks
        let priority: Int32 = 63  // relative prio
        
        pthread_set_qos_class_self_np(qosClass, priority)
    }
     */
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .fixedSize()
        }
        .windowResizability(.contentSize) // Ensures the window fits content size
    }
}
