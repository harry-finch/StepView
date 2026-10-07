import Cocoa
import StepCADCore

final class DropView: NSView {
    var onFileDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = sender.draggedFileURL, isStepFile(url) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggedFileURL, isStepFile(url) else {
            return false
        }
        onFileDropped?(url)
        return true
    }

    private func isStepFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "step" || ext == "stp"
    }
}

private extension NSDraggingInfo {
    var draggedFileURL: URL? {
        guard let pasteboard = draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil),
              let url = pasteboard.first as? URL else {
            return nil
        }
        return url
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate {

    private var cadView: CADSceneView!
    private var dropOverlayView: DropView!
    private var emptyStateLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "StepView"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)

        self.init(window: window)
        window.delegate = self
        setupUI()
        setupToolbar()
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        // 1. Vue 3D SceneKit
        cadView = CADSceneView(frame: contentView.bounds)
        cadView.autoresizingMask = [.width, .height]
        contentView.addSubview(cadView)

        // 2. Overlay Drag & Drop
        dropOverlayView = DropView(frame: contentView.bounds)
        dropOverlayView.autoresizingMask = [.width, .height]
        dropOverlayView.onFileDropped = { [weak self] url in
            self?.loadFile(at: url)
        }
        contentView.addSubview(dropOverlayView)

        // 3. État vide informatif
        emptyStateLabel = NSTextField(labelWithString: "Glissez-déposez un fichier .step ou .stp ici\nou cliquez sur « Ouvrir » dans la barre d'outils")
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyStateLabel)

        // 4. Spinner de chargement
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isHidden = true
        contentView.addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 50)
        ])
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "StepViewMainToolbar")
        toolbar.displayMode = .iconAndLabel
        toolbar.delegate = self
        window?.toolbar = toolbar
    }

    // MARK: - Actions
    @objc func openDocumentAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = []
        if let stepType = UTType(filenameExtension: "step") { types.append(stepType) }
        if let stpType = UTType(filenameExtension: "stp") { types.append(stpType) }
        panel.allowedContentTypes = types

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(at: url)
        }
    }

    @objc func resetCameraAction() {
        cadView.resetCamera(animated: true)
    }

    @objc func toggleWireframeAction() {
        cadView.toggleWireframe()
    }

    func loadFile(at url: URL) {
        emptyStateLabel.isHidden = true
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        window?.title = "StepView – \(url.lastPathComponent)"
        NSLog("[StepView] Début du chargement du fichier: %@", url.path)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let mesh = try CADMeshBridge.loadStepMesh(from: url, linearDeflection: 0.0)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.isHidden = true
                    self.cadView.display(meshData: mesh, fileName: url.lastPathComponent)
                    NSLog("[StepView] Affichage réussi pour: %@", url.lastPathComponent)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.isHidden = true
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Impossible d'ouvrir le fichier"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    self.emptyStateLabel.isHidden = false
                    NSLog("[StepView] Erreur lors de l'ouverture: %@", error.localizedDescription)
                }
            }
        }
    }
}

import UniformTypeIdentifiers

extension NSToolbarItem.Identifier {
    static let openStepItem = NSToolbarItem.Identifier("OpenStepItem")
    static let resetStepItem = NSToolbarItem.Identifier("ResetStepItem")
    static let wireframeStepItem = NSToolbarItem.Identifier("WireframeStepItem")
}

// MARK: - NSToolbarDelegate
extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.openStepItem, .flexibleSpace, .resetStepItem, .wireframeStepItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.openStepItem, .resetStepItem, .wireframeStepItem, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .openStepItem:
            item.label = "Ouvrir"
            item.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "Ouvrir un fichier")
            item.action = #selector(openDocumentAction)
            item.target = self
        case .resetStepItem:
            item.label = "Recadrer"
            item.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Recadrer la caméra")
            item.action = #selector(resetCameraAction)
            item.target = self
        case .wireframeStepItem:
            item.label = "Filaire"
            item.image = NSImage(systemSymbolName: "cube.transparent", accessibilityDescription: "Basculer affichage filaire")
            item.action = #selector(toggleWireframeAction)
            item.target = self
        default:
            return nil
        }
        return item
    }
}
