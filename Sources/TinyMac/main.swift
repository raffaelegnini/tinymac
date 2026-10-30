import AppKit
import TinyMacCore

let app = NSApplication.shared
let controller = TinyMacController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
