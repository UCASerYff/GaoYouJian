import AppKit
import Foundation

// Request a normal Cocoa termination only for this application's exact location.
// The app can reject the request while sending or if a draft cannot be saved.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: QuitApp.swift /Applications/搞邮件.app\n", stderr)
    exit(2)
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let matching = NSRunningApplication.runningApplications(withBundleIdentifier: "com.gaoseries.GaoYouJian").filter {
    $0.bundleURL?.standardizedFileURL == destination
}
for application in matching {
    guard application.terminate() else {
        fputs("搞邮件暂时无法正常退出，安装已中止。\n", stderr)
        exit(1)
    }
}
