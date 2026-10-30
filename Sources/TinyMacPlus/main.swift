import AppKit

let app = NSApplication.shared
let controller = PlusController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
