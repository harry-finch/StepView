import Cocoa
import SceneKit
import simd
import StepCADCore

public final class CADSceneView: SCNView {

    // MARK: - Propriétés de la Scène
    private let modelPivotNode = SCNNode()
    private var meshNode: SCNNode?
    private var groundPlaneNode: SCNNode?
    private let cameraNode = SCNNode()
    private let camera = SCNCamera()

    // MARK: - Propriétés HUD
    private let hudLabel = NSTextField(labelWithString: "")
    private var currentData: CADMeshData?
    private var isWireframeMode: Bool = false

    // MARK: - Initialisation
    public override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let scn = SCNScene()
        self.scene = scn
        self.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1.0)
        self.antialiasingMode = .multisampling4X
        self.allowsCameraControl = true
        self.autoenablesDefaultLighting = false

        scn.rootNode.addChildNode(modelPivotNode)

        // Caméra
        camera.fieldOfView = 45.0
        camera.zNear = 0.1
        camera.zFar = 1000.0
        cameraNode.camera = camera
        scn.rootNode.addChildNode(cameraNode)
        self.pointOfView = cameraNode
        self.defaultCameraController.target = SCNVector3(0, 0, 0)

        setupStudioLighting(in: scn)
        setupHUD()
    }

    // MARK: - Éclairage Studio PBR
    private func setupStudioLighting(in scn: SCNScene) {
        // Ambiance douce
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(calibratedWhite: 0.22, alpha: 1.0)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scn.rootNode.addChildNode(ambientNode)

        // Key Light (Lumière principale avec ombres portées)
        let key = SCNLight()
        key.type = .directional
        key.color = NSColor(calibratedWhite: 0.88, alpha: 1.0)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 3.5
        key.shadowColor = NSColor.black.withAlphaComponent(0.45)

        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-CGFloat.pi / 3.0, CGFloat.pi / 4.0, 0)
        scn.rootNode.addChildNode(keyNode)

        // Fill Light (Lumière de débouchage bleutée subtile)
        let fill = SCNLight()
        fill.type = .directional
        fill.color = NSColor(calibratedRed: 0.45, green: 0.50, blue: 0.55, alpha: 1.0)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-CGFloat.pi / 4.0, -CGFloat.pi / 2.0, 0)
        scn.rootNode.addChildNode(fillNode)

        // Rim Light (Détachement des arêtes et chanfreins)
        let rim = SCNLight()
        rim.type = .directional
        rim.color = NSColor(calibratedWhite: 0.40, alpha: 1.0)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(CGFloat.pi / 4.0, CGFloat.pi, 0)
        scn.rootNode.addChildNode(rimNode)
    }

    private func setupHUD() {
        hudLabel.isBezeled = false
        hudLabel.drawsBackground = true
        hudLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        hudLabel.textColor = NSColor(calibratedWhite: 0.9, alpha: 1.0)
        hudLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        hudLabel.wantsLayer = true
        hudLabel.layer?.cornerRadius = 6.0
        hudLabel.layer?.masksToBounds = true
        hudLabel.alignment = .left
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.isHidden = true
        addSubview(hudLabel)

        NSLayoutConstraint.activate([
            hudLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hudLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    // MARK: - Affichage & Cadrage
    public func display(meshData: CADMeshData, fileName: String? = nil) {
        self.currentData = meshData

        // Suppression de l'ancienne géométrie
        meshNode?.removeFromParentNode()
        groundPlaneNode?.removeFromParentNode()

        guard let geometry = CADGeometryBuilder.buildGeometry(from: meshData, isWireframe: isWireframeMode) else {
            return
        }

        let newMeshNode = SCNNode(geometry: geometry)
        self.meshNode = newMeshNode
        modelPivotNode.addChildNode(newMeshNode)

        // Bounding box et dimensions
        let bMin = meshData.boundingBoxMin
        let bMax = meshData.boundingBoxMax
        let center = (bMin + bMax) * 0.5
        let extents = bMax - bMin
        let radius = simd_length(extents) * 0.5

        // Centrage du modèle à l'origine locale
        newMeshNode.position = SCNVector3(-center.x, -center.y, -center.z)

        // Plan de sol receveur d'ombres
        let groundSize = CGFloat(radius * 5.0)
        let groundGeo = SCNPlane(width: groundSize, height: groundSize)
        groundGeo.cornerRadius = 0
        let groundMat = SCNMaterial()
        groundMat.lightingModel = .physicallyBased
        groundMat.diffuse.contents = NSColor(calibratedWhite: 0.16, alpha: 1.0)
        groundMat.metalness.contents = NSNumber(value: 0.0)
        groundMat.roughness.contents = NSNumber(value: 0.9)
        groundGeo.materials = [groundMat]

        let ground = SCNNode(geometry: groundGeo)
        ground.eulerAngles = SCNVector3(-CGFloat.pi / 2.0, 0, 0)
        ground.position = SCNVector3(0, -extents.y * 0.5 - (radius * 0.01), 0)
        modelPivotNode.addChildNode(ground)
        self.groundPlaneNode = ground

        // Recadrage instantané de la caméra (sans mouvement gênant)
        resetCamera(radius: radius, animated: false)

        // Mise à jour de l'affichage HUD
        updateHUD(fileName: fileName, meshData: meshData)
    }

    public func resetCamera(radius: Float? = nil, animated: Bool = false) {
        guard let data = currentData else { return }
        let extents = data.boundingBoxMax - data.boundingBoxMin
        let targetRadius = radius ?? (simd_length(extents) * 0.5)

        let fovRad = Double(camera.fieldOfView) * .pi / 180.0
        let distance = Double(targetRadius) / sin(fovRad / 2.0) * 1.35

        // Vue isométrique classique de bureau d'études (30° élévation, 45° azimut)
        let elevation: Double = .pi / 6.0
        let azimuth: Double = .pi / 4.0

        let posX = distance * cos(elevation) * sin(azimuth)
        let posY = distance * sin(elevation)
        let posZ = distance * cos(elevation) * cos(azimuth)

        SCNTransaction.begin()
        if animated {
            SCNTransaction.animationDuration = 0.35
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        } else {
            SCNTransaction.animationDuration = 0.0
            SCNTransaction.disableActions = true
        }

        cameraNode.position = SCNVector3(posX, posY, posZ)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        camera.zNear = max(0.01, distance * 0.01)
        camera.zFar = distance * 25.0
        SCNTransaction.commit()

        self.pointOfView = cameraNode
        self.defaultCameraController.target = SCNVector3(0, 0, 0)
    }

    public func toggleWireframe() {
        isWireframeMode.toggle()
        guard let data = currentData else { return }
        if let newGeo = CADGeometryBuilder.buildGeometry(from: data, isWireframe: isWireframeMode) {
            meshNode?.geometry = newGeo
        }
    }

    private func updateHUD(fileName: String?, meshData: CADMeshData) {
        let dim = meshData.dimensions
        let triCount = meshData.triangleCount
        let vertCount = meshData.vertexCount

        let triFormatted = triCount > 1000 ? String(format: "%.1f k", Double(triCount) / 1000.0) : "\(triCount)"
        let vertFormatted = vertCount > 1000 ? String(format: "%.1f k", Double(vertCount) / 1000.0) : "\(vertCount)"

        var text = ""
        if let name = fileName {
            text += "  Fichier : \(name)\n"
        }
        text += String(format: "  Dimensions : %.1f × %.1f × %.1f mm\n", dim.x, dim.y, dim.z)
        text += "  Triangles : \(triFormatted)  |  Sommets : \(vertFormatted)  "

        hudLabel.stringValue = text
        hudLabel.isHidden = false
    }
}
