import UIKit
import ARKit
import SceneKit

class PointCloudViewController: UIViewController, ARSessionDelegate {
    private let sceneView = ARSCNView()
    private var isRunning = false
    private var useSmoothedDepth = true
    private var stridePixels: Int = 4
    private var maxDistance: Float = 3.0
    private var maxDelta: Float = 0.05
    private var points: [SCNVector3] = []
    private var colors: [Float] = []
    private var pointNode: SCNNode?
    private var meshNode: SCNNode?
    private var startButton: UIButton = UIButton(type: .system)
    private var stopButton: UIButton = UIButton(type: .system)
    private var exportButton: UIButton = UIButton(type: .system)
    private var meshButton: UIButton = UIButton(type: .system)
    private var precisionSlider = UISlider()
    private var distanceSlider = UISlider()
    private var smoothSwitch = UISwitch()
    private var colorSwitch = UISwitch()
    private var precisionLabel = UILabel()
    private var distanceLabel = UILabel()
    private var isProcessingFrame = false
    private var confidenceThreshold: UInt8 = 128
    private var useColor = true
    private var lastFrame: ARFrame?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            let l = UILabel()
            l.text = "此设备不支持点云扫描"
            l.textColor = .white
            l.textAlignment = .center
            l.frame = view.bounds
            l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(l)
            return
        }
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.session.delegate = self
        sceneView.preferredFramesPerSecond = 60
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)

        startButton.setTitle("开始扫描", for: .normal)
        stopButton.setTitle("停止扫描", for: .normal)
        exportButton.setTitle("导出点云", for: .normal)
        meshButton.setTitle("生成网格", for: .normal)
        precisionLabel.textColor = .white
        distanceLabel.textColor = .white
        precisionLabel.text = "精度:4"
        distanceLabel.text = "距离:3.0m"
        precisionSlider.minimumValue = 1
        precisionSlider.maximumValue = 8
        precisionSlider.value = 4
        distanceSlider.minimumValue = 0.5
        distanceSlider.maximumValue = 5.0
        distanceSlider.value = 3.0
        smoothSwitch.isOn = true
        colorSwitch.isOn = true
        let confidenceLabel = UILabel()
        confidenceLabel.textColor = .white
        confidenceLabel.text = "可信度:128"
        let confidenceSlider = UISlider()
        confidenceSlider.minimumValue = 0
        confidenceSlider.maximumValue = 255
        confidenceSlider.value = 128

        let controlsStack = UIStackView(arrangedSubviews: [
            labelWithControl(title: "平滑", control: smoothSwitch),
            labelWithControl(title: "颜色", control: colorSwitch),
            labeledSlider(label: precisionLabel, slider: precisionSlider),
            labeledSlider(label: distanceLabel, slider: distanceSlider),
            labeledSlider(label: confidenceLabel, slider: confidenceSlider)
        ])
        controlsStack.axis = .vertical
        controlsStack.alignment = .fill
        controlsStack.spacing = 8
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsStack)

        let actionsStack = UIStackView(arrangedSubviews: [startButton, stopButton, exportButton, meshButton])
        actionsStack.axis = .horizontal
        actionsStack.alignment = .fill
        actionsStack.distribution = .fillEqually
        actionsStack.spacing = 12
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionsStack)

        NSLayoutConstraint.activate([
            controlsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            controlsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            actionsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            actionsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actionsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            actionsStack.heightAnchor.constraint(equalToConstant: 50)
        ])

        startButton.addTarget(self, action: #selector(startScan), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopScan), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportPointCloud), for: .touchUpInside)
        meshButton.addTarget(self, action: #selector(generateMesh), for: .touchUpInside)
        precisionSlider.addTarget(self, action: #selector(precisionChanged), for: .valueChanged)
        distanceSlider.addTarget(self, action: #selector(distanceChanged), for: .valueChanged)
        smoothSwitch.addTarget(self, action: #selector(smoothChanged), for: .valueChanged)
        confidenceSlider.addTarget(self, action: #selector(confidenceChanged(_:)), for: .valueChanged)
        confidenceSlider.tag = 1001
        confidenceLabel.tag = 1002
        colorSwitch.addTarget(self, action: #selector(colorChanged), for: .valueChanged)
    }

    private func labelWithControl(title: String, control: UIView) -> UIStackView {
        let t = UILabel()
        t.textColor = .white
        t.text = title
        let s = UIStackView(arrangedSubviews: [t, control])
        s.axis = .horizontal
        s.alignment = .center
        s.spacing = 8
        return s
    }

    private func labeledSlider(label: UILabel, slider: UISlider) -> UIStackView {
        let s = UIStackView(arrangedSubviews: [label, slider])
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = 4
        return s
    }

    @objc private func precisionChanged() {
        stridePixels = max(1, Int(precisionSlider.value.rounded()))
        precisionLabel.text = "精度:\(stridePixels)"
    }

    @objc private func distanceChanged() {
        maxDistance = distanceSlider.value
        let v = String(format: "%.1f", maxDistance)
        distanceLabel.text = "距离:\(v)m"
    }

    @objc private func smoothChanged() {
        useSmoothedDepth = smoothSwitch.isOn
        if isRunning { restartSession() }
    }
    
    @objc private func confidenceChanged(_ slider: UISlider) {
        let v = Int(slider.value.rounded())
        if let label = view.viewWithTag(1002) as? UILabel {
            label.text = "可信度:\(v)"
        }
        confidenceThreshold = UInt8(v)
    }

    @objc private func startScan() {
        points.removeAll()
        colors.removeAll()
        pointNode?.removeFromParentNode()
        pointNode = nil
        meshNode?.removeFromParentNode()
        meshNode = nil
        isRunning = true
        restartSession()
    }

    private func restartSession() {
        let config = ARWorldTrackingConfiguration()
        if useSmoothedDepth {
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        } else {
            config.frameSemantics = [.sceneDepth]
        }
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    @objc private func stopScan() {
        isRunning = false
        sceneView.session.pause()
    }
    
    @objc private func colorChanged() {
        useColor = colorSwitch.isOn
    }

    @objc private func exportPointCloud() {
        guard points.count > 0 else { return }
        var text = "ply\nformat ascii 1.0\nelement vertex \(points.count)\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        for p in points {
            text.append("\(p.x) \(p.y) \(p.z)\n")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "PointCloud_\(formatter.string(from: Date())).ply"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = avc.popoverPresentationController {
                pop.sourceView = exportButton
                pop.sourceRect = exportButton.bounds
            }
            present(avc, animated: true)
        } catch {
            let alert = UIAlertController(title: "导出失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            present(alert, animated: true)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrame = frame
        if !isRunning { return }
        if isProcessingFrame { return }
        isProcessingFrame = true
        DispatchQueue.global(qos: .userInitiated).async {
            self.processFrame(frame)
            DispatchQueue.main.async {
                self.updatePointNode()
                self.isProcessingFrame = false
            }
        }
    }

    private func processFrame(_ frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return }
        let depth = sceneDepth.depthMap
        let confidence = sceneDepth.confidenceMap
        let image = frame.capturedImage
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        if confidence != nil { CVPixelBufferLockBaseAddress(confidence!, .readOnly) }
        if useColor { CVPixelBufferLockBaseAddress(image, .readOnly) }
        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        let base = CVPixelBufferGetBaseAddress(depth)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)
        var confBase: UnsafeMutableRawPointer? = nil
        var confBytesPerRow: Int = 0
        if let c = confidence {
            confBase = CVPixelBufferGetBaseAddress(c)
            confBytesPerRow = CVPixelBufferGetBytesPerRow(c)
        }
        var yBase: UnsafeMutableRawPointer? = nil
        var yBytesPerRow: Int = 0
        var yWidth: Int = 0
        var yHeight: Int = 0
        if useColor {
            yBase = CVPixelBufferGetBaseAddressOfPlane(image, 0)
            yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
            yWidth = CVPixelBufferGetWidthOfPlane(image, 0)
            yHeight = CVPixelBufferGetHeightOfPlane(image, 0)
        }
        let fx = frame.camera.intrinsics.columns.0.x
        let fy = frame.camera.intrinsics.columns.1.y
        let cx = frame.camera.intrinsics.columns.2.x
        let cy = frame.camera.intrinsics.columns.2.y
        let cameraTransform = frame.camera.transform
        var newPoints: [SCNVector3] = []
        var newColors: [Float] = []
        for y in stride(from: 0, to: h, by: stridePixels) {
            let rowPtr = base!.advanced(by: y * bytesPerRow)
            let row = rowPtr.bindMemory(to: Float32.self, capacity: w)
            for x in stride(from: 0, to: w, by: stridePixels) {
                let z = row[x]
                if z.isNaN || z <= 0 { continue }
                if z > maxDistance { continue }
                if let cbase = confBase {
                    let crowPtr = cbase.advanced(by: y * confBytesPerRow)
                    let crow = crowPtr.bindMemory(to: UInt8.self, capacity: w)
                    if crow[x] < confidenceThreshold { continue }
                }
                let xc = (Float(x) - cx) * z / fx
                let yc = (Float(y) - cy) * z / fy
                let pc = simd_float4(xc, yc, -z, 1)
                let pw = cameraTransform * pc
                newPoints.append(SCNVector3(pw.x, pw.y, pw.z))
                if useColor {
                    let xi = Int(Float(x) / Float(w) * Float(yWidth))
                    let yi = Int(Float(y) / Float(h) * Float(yHeight))
                    let yrowPtr = yBase!.advanced(by: yi * yBytesPerRow)
                    let yrow = yrowPtr.bindMemory(to: UInt8.self, capacity: yWidth)
                    let intensity = Float(yrow[min(max(xi, 0), yWidth - 1)]) / 255.0
                    newColors.append(contentsOf: [intensity, intensity, intensity, 1.0])
                } else {
                    newColors.append(contentsOf: [1.0, 1.0, 1.0, 1.0])
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(depth, .readOnly)
        if confidence != nil { CVPixelBufferUnlockBaseAddress(confidence!, .readOnly) }
        if useColor { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        points.append(contentsOf: newPoints)
        colors.append(contentsOf: newColors)
        if points.count > 300000 {
            let excess = points.count - 300000
            points.removeFirst(excess)
            colors.removeFirst(excess * 4)
        }
    }

    private func updatePointNode() {
        guard points.count > 0 else { return }
        let vertexSource = SCNGeometrySource(vertices: points)
        var indices = [Int32]()
        indices.reserveCapacity(points.count)
        for i in 0..<points.count { indices.append(Int32(i)) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        var sources: [SCNGeometrySource] = [vertexSource]
        if colors.count == points.count * 4 {
            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: points.count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4)
            sources.append(colorSource)
        }
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]
        if let node = pointNode {
            node.geometry = geometry
        } else {
            let node = SCNNode(geometry: geometry)
            sceneView.scene.rootNode.addChildNode(node)
            pointNode = node
        }
    }
    
    @objc private func generateMesh() {
        guard let frame = lastFrame, let sceneDepth = frame.sceneDepth else { return }
        let depth = sceneDepth.depthMap
        let confidence = sceneDepth.confidenceMap
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        if confidence != nil { CVPixelBufferLockBaseAddress(confidence!, .readOnly) }
        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        let base = CVPixelBufferGetBaseAddress(depth)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)
        var confBase: UnsafeMutableRawPointer? = nil
        var confBytesPerRow: Int = 0
        if let c = confidence {
            confBase = CVPixelBufferGetBaseAddress(c)
            confBytesPerRow = CVPixelBufferGetBytesPerRow(c)
        }
        let fx = frame.camera.intrinsics.columns.0.x
        let fy = frame.camera.intrinsics.columns.1.y
        let cx = frame.camera.intrinsics.columns.2.x
        let cy = frame.camera.intrinsics.columns.2.y
        let cameraTransform = frame.camera.transform
        let step = max(1, stridePixels)
        let rows = h / step
        let cols = w / step
        var verts: [SCNVector3] = []
        var depths: [Float] = []
        var mapping = [Int](repeating: -1, count: rows * cols)
        var idx = 0
        for ry in 0..<rows {
            let y = ry * step
            let rowPtr = base!.advanced(by: y * bytesPerRow)
            let row = rowPtr.bindMemory(to: Float32.self, capacity: w)
            for rx in 0..<cols {
                let x = rx * step
                let z = row[x]
                if z.isNaN || z <= 0 { continue }
                if z > maxDistance { continue }
                if let cbase = confBase {
                    let crowPtr = cbase.advanced(by: y * confBytesPerRow)
                    let crow = crowPtr.bindMemory(to: UInt8.self, capacity: w)
                    if crow[x] < confidenceThreshold { continue }
                }
                let xc = (Float(x) - cx) * z / fx
                let yc = (Float(y) - cy) * z / fy
                let pc = simd_float4(xc, yc, -z, 1)
                let pw = cameraTransform * pc
                verts.append(SCNVector3(pw.x, pw.y, pw.z))
                depths.append(z)
                mapping[ry * cols + rx] = idx
                idx += 1
            }
        }
        var triIndices = [Int32]()
        for ry in 0..<(rows - 1) {
            for rx in 0..<(cols - 1) {
                let i00 = mapping[ry * cols + rx]
                let i10 = mapping[ry * cols + rx + 1]
                let i01 = mapping[(ry + 1) * cols + rx]
                let i11 = mapping[(ry + 1) * cols + rx + 1]
                if i00 >= 0 && i10 >= 0 && i01 >= 0 {
                    let d0 = depths[i00]
                    let d1 = depths[i10]
                    let d2 = depths[i01]
                    if abs(d0 - d1) < maxDelta && abs(d0 - d2) < maxDelta {
                        triIndices.append(Int32(i00)); triIndices.append(Int32(i10)); triIndices.append(Int32(i01))
                    }
                }
                if i10 >= 0 && i11 >= 0 && i01 >= 0 {
                    let d1 = depths[i10]
                    let d3 = depths[i11]
                    let d2 = depths[i01]
                    if abs(d1 - d3) < maxDelta && abs(d1 - d2) < maxDelta {
                        triIndices.append(Int32(i10)); triIndices.append(Int32(i11)); triIndices.append(Int32(i01))
                    }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(depth, .readOnly)
        if confidence != nil { CVPixelBufferUnlockBaseAddress(confidence!, .readOnly) }
        guard verts.count > 0 && triIndices.count > 0 else { return }
        let vSource = SCNGeometrySource(vertices: verts)
        let tElement = SCNGeometryElement(indices: triIndices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vSource], elements: [tElement])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.lightGray
        geometry.materials = [material]
        meshNode?.removeFromParentNode()
        let node = SCNNode(geometry: geometry)
        sceneView.scene.rootNode.addChildNode(node)
        meshNode = node
    }
}
