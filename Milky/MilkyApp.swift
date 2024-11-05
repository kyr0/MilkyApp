import SwiftUI

let kAppSubsystem = "de.aronhomberg.Milky"

@main
struct MilkyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .fixedSize()
        }
        .windowResizability(.contentSize) // Ensures the window fits content size
    }
}
