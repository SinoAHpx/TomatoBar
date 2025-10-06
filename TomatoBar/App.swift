import SwiftUI
import LaunchAtLogin

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
        LaunchAtLogin.migrateIfNeeded()
        logger.append(event: TBLogEventAppStart())
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class TBStatusItem: NSObject, NSApplicationDelegate {
    var popover: NSPopover? {
        return _popover
    }
    private var _popover = NSPopover()
    private var statusBarItem: NSStatusItem?
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let view = TBPopoverView()

        _popover.behavior = .transient
        _popover.contentViewController = NSViewController()
        _popover.contentViewController?.view = NSHostingView(rootView: view)
        if let contentViewController = _popover.contentViewController {
            _popover.contentSize.height = contentViewController.view.intrinsicContentSize.height
            _popover.contentSize.width = 240
        }

        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(name: .idle)
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))
    }

    func setTitle(title: String?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.9
        paragraphStyle.alignment = NSTextAlignment.center

        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [
                NSAttributedString.Key.font: digitFont,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
        )
        statusBarItem?.button?.attributedTitle = attributedTitle
    }

    func setIcon(name: NSImage.Name) {
        statusBarItem?.button?.image = NSImage(named: name)
    }

    func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            _popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            _popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover(_ sender: AnyObject?) {
        _popover.performClose(sender)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if _popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
}
