import AppKit

class DetachedWindow: NSWindow {
    let detachedViewController: DetachedViewController

    init(contentRect: NSRect) {
        detachedViewController = DetachedViewController()
        
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        /// Set up the root view controller for this window
        contentViewController = detachedViewController
        title = "Milky Music Visualizer by Aron Homberg"
        makeKeyAndOrderFront(nil)
    }
}
