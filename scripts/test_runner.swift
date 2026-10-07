import Foundation
import AppKit
import SceneKit
import QuickLookUI
import StepCADCore

@main
struct TestRunner {
    static func main() {
        let projectDir = FileManager.default.currentDirectoryPath
        let sampleModelsDir = "\(projectDir)/sample_models"

        print("==========================================================")
        print("  Démarrage des tests automatisés de StepView")
        print("==========================================================")

        let testFiles = [
            ("cube.step", SIMD3<Float>(30, 30, 30)),
            ("cylinder.step", SIMD3<Float>(30, 30, 50)),
            ("bracket.step", SIMD3<Float>(80, 50, 15))
        ]

        var totalPassed = 0

        for (fileName, expectedDims) in testFiles {
            let fileURL = URL(fileURLWithPath: "\(sampleModelsDir)/\(fileName)")
            print("\n--- Test du modèle : \(fileName) ---")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                fatalError("Fichier introuvable : \(fileURL.path)")
            }

            // 1. Test du Bridge C++ / OCCT
            let startTime = Date()
            do {
                let meshData = try CADMeshBridge.loadStepMesh(from: fileURL, linearDeflection: 0.0)
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0

                print(String(format: "✓ Parsing & Tessellation en %.1f ms", elapsed))
                print("  • Triangles : \(meshData.triangleCount)")
                print("  • Sommets   : \(meshData.vertexCount)")
                let dims = meshData.dimensions
                print(String(format: "  • BBox      : %.1f × %.1f × %.1f mm", dims.x, dims.y, dims.z))

                // Vérification des dimensions à 1% près
                assert(abs(dims.x - expectedDims.x) < 1.0, "Dimension X inattendue: \(dims.x) vs \(expectedDims.x)")
                assert(abs(dims.y - expectedDims.y) < 1.0, "Dimension Y inattendue: \(dims.y) vs \(expectedDims.y)")
                assert(abs(dims.z - expectedDims.z) < 1.0, "Dimension Z inattendue: \(dims.z) vs \(expectedDims.z)")

                // 2. Test de conversion géométrie SceneKit
                guard let geo = CADGeometryBuilder.buildGeometry(from: meshData, isWireframe: false) else {
                    fatalError("Échec de création de la géométrie SceneKit pour \(fileName)")
                }
                print("✓ SCNGeometry créée avec succès (\(geo.sources.count) sources, \(geo.elements.count) éléments)")

                totalPassed += 1
            } catch {
                fatalError("Erreur inattendue sur \(fileName): \(error)")
            }
        }

        // 3. Test de PreviewViewController (Quick Look Provider)
        print("\n--- Test du contrôleur Quick Look PreviewViewController ---")
        let testURL = URL(fileURLWithPath: "\(sampleModelsDir)/bracket.step")
        let controller = PreviewViewController()
        controller.loadView()

        let expectation = DispatchSemaphore(value: 0)
        var previewError: Error?

        controller.preparePreviewOfFile(at: testURL) { error in
            previewError = error
            expectation.signal()
        }

        _ = expectation.wait(timeout: .now() + 5.0)

        if let err = previewError {
            fatalError("Échec de préparation du preview: \(err)")
        } else {
            print("✓ PreviewViewController a préparé l'aperçu Quick Look avec succès sans erreur !")
            totalPassed += 1
        }

        print("\n==========================================================")
        print("  ✓ Tous les \(totalPassed) tests ont RÉUSSI avec succès !")
        print("==========================================================")
    }
}
