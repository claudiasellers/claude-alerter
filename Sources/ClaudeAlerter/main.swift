import Foundation

// `ClaudeAlerter --hook <Event>` is called by Claude Code hooks; it must stay fast and headless.
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--hook" {
    Hook.run(event: args[2])
    exit(0)
}

ClaudeAlerterApp.main()
