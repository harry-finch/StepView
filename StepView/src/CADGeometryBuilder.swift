import Foundation
import SceneKit
import simd
import StepCADCore

public enum CADGeometryBuilder {

    /// Construit une SCNGeometry SceneKit depuis les données de maillage brutes (Metal-compliant)
    public static func buildGeometry(from data: CADMeshData, isWireframe: Bool = false) -> SCNGeometry? {
        guard data.vertexCount > 0, data.triangleCount > 0 else { return nil }

        let vertexSource = SCNGeometrySource(
            data: data.vertexData,
            semantic: .vertex,
            vectorCount: Int(data.vertexCount),
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<simd_float3>.stride
        )

        let normalSource = SCNGeometrySource(
            data: data.normalData,
            semantic: .normal,
            vectorCount: Int(data.vertexCount),
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<simd_float3>.stride
        )

        let element = SCNGeometryElement(
            data: data.indexData,
            primitiveType: .triangles,
            primitiveCount: Int(data.triangleCount),
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        // Configuration du matériau PBR studio CAO
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedRed: 0.76, green: 0.80, blue: 0.84, alpha: 1.0)
        material.metalness.contents = NSNumber(value: 0.18)
        material.roughness.contents = NSNumber(value: 0.38)
        material.isDoubleSided = true
        material.fillMode = isWireframe ? .lines : .fill

        geometry.materials = [material]
        return geometry
    }

    /// Crée un repère d'axes orthonormés (X: Rouge, Y: Vert, Z: Bleu)
    public static func buildCoordinateAxes(length: CGFloat) -> SCNNode {
        let root = SCNNode()

        func makeAxis(color: NSColor, orientation: SCNVector3) -> SCNNode {
            let cylinder = SCNCylinder(radius: length * 0.015, height: length)
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .constant
            cylinder.materials = [mat]

            let node = SCNNode(geometry: cylinder)
            node.eulerAngles = orientation
            node.position = SCNVector3(0, length / 2, 0)

            let wrapper = SCNNode()
            wrapper.addChildNode(node)
            return wrapper
        }

        // X (Rouge)
        let xAxis = makeAxis(color: .systemRed, orientation: SCNVector3(0, 0, -CGFloat.pi / 2.0))
        // Y (Vert)
        let yAxis = makeAxis(color: .systemGreen, orientation: SCNVector3(0, 0, 0))
        // Z (Bleu)
        let zAxis = makeAxis(color: .systemBlue, orientation: SCNVector3(CGFloat.pi / 2.0, 0, 0))

        root.addChildNode(xAxis)
        root.addChildNode(yAxis)
        root.addChildNode(zAxis)
        return root
    }
}
