import Cocoa
import Quartz
import QuickLookUI
import StepCADCore

@objc(PreviewViewController)
public final class PreviewViewController: NSViewController, QLPreviewingController {

    private var cadView: CADSceneView!
    private var progressIndicator: NSProgressIndicator!
    private var errorLabel: NSTextField!
    // Garde-fous Quick Look (budget mémoire/temps serré de l'extension)
    private static let maxFileSize: Int64 = 150 * 1024 * 1024   // 150 Mo
    private static let maxTriangles: UInt = 2_000_000           // ~100 Mo de buffers CPU, reste fluide dans SceneKit
    private static let relativeDeflection = -0.005              // 0.5% de la diagonale (app : 0.2%) : ~2x moins de triangles
    private let loadingQueue = DispatchQueue(label: "com.stepview.tessellation", qos: .userInitiated)

    public override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        containerView.wantsLayer = true

        // 1. Vue 3D SceneKit
        cadView = CADSceneView(frame: containerView.bounds)
        cadView.autoresizingMask = [.width, .height]
        containerView.addSubview(cadView)

        // 2. Spinner de chargement
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(progressIndicator)

        // 3. Label d'erreur
        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        errorLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -24)
        ])

        self.view = containerView
    }

    // MARK: - QLPreviewingController

    @objc
    public func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) > Self.maxFileSize {
            let message = "Fichier trop volumineux pour l'aperçu rapide (\(size / 1_048_576) Mo, limite \(Self.maxFileSize / 1_048_576) Mo). Ouvrez-le dans StepView."
            let error = NSError(domain: "com.stepview.error", code: 1008,
                                userInfo: [NSLocalizedDescriptionKey: message])
            DispatchQueue.main.async {
                self.progressIndicator.isHidden = true
                self.showError(message)
                handler(error)
            }
            return
        }

        progressIndicator.startAnimation(nil)
        progressIndicator.isHidden = false
        errorLabel.isHidden = true

        loadingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Déflexion négative = fraction de la diagonale ; plafond de triangles (erreur 1006 au-delà)
                let meshData = try CADMeshBridge.loadStepMesh(from: url,
                                                              linearDeflection: Self.relativeDeflection,
                                                              maxTriangles: Self.maxTriangles)

                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.isHidden = true
                    self.cadView.display(meshData: meshData, fileName: url.lastPathComponent)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.isHidden = true
                    self.showError("Impossible de générer l'aperçu : \(error.localizedDescription)")
                    handler(error)
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }
}
