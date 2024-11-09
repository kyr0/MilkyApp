import AppKit

class DetachedWindow: NSWindow {
    let detachedViewController: DetachedViewController
    private var trackingArea: NSTrackingArea?
    
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
        
        // Set up the mouse tracking area
        setupMouseTracking()
    }
    
    private func setupMouseTracking() {
        trackingArea = NSTrackingArea(
            rect: self.contentView!.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            self.contentView?.addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.hide()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.unhide()
    }
    
    deinit {
        if let trackingArea = trackingArea {
            self.contentView?.removeTrackingArea(trackingArea)
        }
    }
}
