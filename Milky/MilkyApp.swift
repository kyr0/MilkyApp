import SwiftUI

let kAppSubsystem = "de.aronhomberg.Milky"

@main
struct MilkyApp: App {
    
    init() {
        
        print("Started")
        //setMainThreadHighPriority();
        //renice();
    }
    
    /*
    func setMainThreadHighPriority() {
        let qosClass: qos_class_t = QOS_CLASS_USER_INTERACTIVE  // High QoS for UI/foreground tasks
        let priority: Int32 = 63  // relative prio
        
        pthread_set_qos_class_self_np(qosClass, priority)
    }
    
    func renice() {
        
        // Get the current PID
        let pid = getpid()

        // Get the start command (the arguments used to start the process)
        let startCommand = ProcessInfo.processInfo.arguments.joined(separator: " ")
        
        // prioritize
         NSAppleScript(source: "do shell script \"sudo renice -n -20 -p  " + String(pid) + "\" with administrator " +
             "privileges")!.executeAndReturnError(nil)
        
        print("exec res")
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
