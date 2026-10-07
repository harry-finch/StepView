import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var hasHandledInitialFile = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        setupMainMenu()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        hasHandledInitialFile = true
        let url = URL(fileURLWithPath: filename)
        let ctrl = getOrCreateMainWindow()
        ctrl.showWindow(nil)
        ctrl.loadFile(at: url)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ctrl = getOrCreateMainWindow()

        if !hasHandledInitialFile {
            // Vérifier si un fichier a été passé via la ligne de commande (CLI)
            var fileFromArgs: URL?
            for arg in CommandLine.arguments.dropFirst() {
                if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg) {
                    fileFromArgs = URL(fileURLWithPath: arg)
                    break
                }
            }

            if let url = fileFromArgs {
                ctrl.loadFile(at: url)
            }
        }

        ctrl.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            getOrCreateMainWindow().showWindow(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func getOrCreateMainWindow() -> MainWindowController {
        if let existing = mainWindowController {
            return existing
        }
        let ctrl = MainWindowController()
        self.mainWindowController = ctrl
        return ctrl
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Menu Application
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "À propos de StepView", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Masquer StepView", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Masquer les autres", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quitter StepView", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Menu Fichier
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Fichier")
        let openItem = NSMenuItem(title: "Ouvrir…", action: #selector(MainWindowController.openDocumentAction), keyEquivalent: "o")
        fileMenu.addItem(openItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Menu Fenêtre
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenêtre")
        windowMenu.addItem(withTitle: "Réduire", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
