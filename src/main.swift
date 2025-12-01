import Cocoa
import Foundation

let app = NSApplication.shared
let delegate = YBarApp()
app.delegate = delegate

var args = CommandLine.arguments
args.removeFirst()

parseCommandLine(args: args, delegate: delegate)

app.run()
