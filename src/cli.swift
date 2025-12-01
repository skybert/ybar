import Foundation

func printHelp() {
    print("""
    ybar - A custom menubar replacement for macOS

    USAGE:
        ybar [OPTIONS]

    OPTIONS:
        --help                  Show this help message
        --version               Show version information
        --conf <file>           Use specified configuration file
        --center-clock          Center the clock on the bar
        --center-workspace      Center the workspace indicator on the bar

    CONFIGURATION:
        By default, ybar reads configuration from ~/.ybar.conf
        See man ybar for configuration options.
    """)
}

func printVersion() {
    print("ybar version \(VERSION)")
}

func parseCommandLine(args: [String], delegate: YBarApp) {
    var i = 0
    while i < args.count {
        let arg = args[i]

        switch arg {
        case "--help", "-h":
            printHelp()
            exit(0)
        case "--version", "-v":
            printVersion()
            exit(0)
        case "--conf", "-c":
            if i + 1 < args.count {
                delegate.configPath = args[i + 1]
                i += 1
            } else {
                print("Error: --conf requires a file path")
                exit(1)
            }
        case "--center-clock":
            delegate.centerClock = true
        case "--center-workspace":
            delegate.centerWorkspace = true
        default:
            print("Error: Unknown option '\(arg)'")
            printHelp()
            exit(1)
        }

        i += 1
    }
}
