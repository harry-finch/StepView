import Cocoa
import Quartz
import QuickLookUI
import StepCADCore

@objc(PreviewViewController)
public final class PreviewViewController: NSViewController, QLPreviewingController {

    private var cadView: CADSceneView!
    private var progressIndicator: NSProgressIndicator!
    private var errorLabel: NSTextField!
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
        progressIndicator.startAnimation(nil)
        progressIndicator.isHidden = false
        errorLabel.isHidden = true

        loadingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // linearDeflection <= 0.0 déclenche le calcul adaptatif automatique
                let meshData = try CADMeshBridge.loadStepMesh(from: url, linearDeflection: 0.0)

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
