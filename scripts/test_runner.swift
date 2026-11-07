import Foundation
import AppKit
import SceneKit
import QuickLookUI
import StepCADCore

/// Vérification de test qui reste active en configuration -O (contrairement à assert).
/// En cas d'échec, affiche le message et termine le processus avec le code 1.
func check(_ cond: Bool, _ msg: String) {
    guard cond else {
        print("✗ \(msg)")
        exit(1)
    }
}

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
        // 3 modèles + 1 preview Quick Look + 1 test négatif
        let expectedTests = testFiles.count + 2

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
                check(abs(dims.x - expectedDims.x) < 1.0, "Dimension X inattendue pour \(fileName): \(dims.x) vs \(expectedDims.x)")
                check(abs(dims.y - expectedDims.y) < 1.0, "Dimension Y inattendue pour \(fileName): \(dims.y) vs \(expectedDims.y)")
                check(abs(dims.z - expectedDims.z) < 1.0, "Dimension Z inattendue pour \(fileName): \(dims.z) vs \(expectedDims.z)")

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

        // Le handler est appelé sur la file principale : il faut faire tourner la run loop
        // (un sémaphore bloquant le thread principal empêcherait son exécution).
        var handlerCalled = false
        var previewError: Error?

        controller.preparePreviewOfFile(at: testURL) { error in
            previewError = error
            handlerCalled = true
        }

        let deadline = Date().addingTimeInterval(10.0)
        while !handlerCalled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        check(handlerCalled, "Délai dépassé (10 s) : le handler de preparePreviewOfFile n'a jamais été appelé")
        check(previewError == nil, "Échec de préparation du preview: \(String(describing: previewError))")
        print("✓ PreviewViewController a préparé l'aperçu Quick Look avec succès sans erreur !")
        totalPassed += 1

        // 4. Test négatif : un fichier non-STEP doit produire une erreur, pas un crash
        print("\n--- Test négatif : fichier non-STEP ---")
        let invalidURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stepview_invalide_\(UUID().uuidString).step")
        do {
            try "Ceci n'est pas un fichier STEP.\n".write(to: invalidURL, atomically: true, encoding: .utf8)
        } catch {
            fatalError("Impossible de créer le fichier temporaire : \(error)")
        }

        var negativeError: Error?
        do {
            _ = try CADMeshBridge.loadStepMesh(from: invalidURL, linearDeflection: 0.0)
        } catch {
            negativeError = error
        }
        try? FileManager.default.removeItem(at: invalidURL)

        check(negativeError != nil, "Un fichier non-STEP aurait dû faire échouer loadStepMesh, mais le chargement a réussi")
        print("✓ Fichier non-STEP rejeté avec une erreur : \(negativeError?.localizedDescription ?? "")")
        totalPassed += 1

        // Bilan final : le code de sortie n'est 0 que si tous les tests sont passés
        let allPassed = totalPassed == expectedTests
        print("\n==========================================================")
        if allPassed {
            print("  ✓ Tous les \(totalPassed) tests ont RÉUSSI avec succès !")
        } else {
            print("  ✗ \(totalPassed) tests sur \(expectedTests) ont réussi")
        }
        print("==========================================================")
        exit(allPassed ? 0 : 1)
    }
}
