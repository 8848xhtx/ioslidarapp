import UIKit
#if canImport(RoomPlan)
import RoomPlan
@available(iOS 16.0, *)
class RoomScanViewController: UIViewController, RoomCaptureViewDelegate {
    private var captureView: RoomCaptureView!
    private let captureSession = RoomCaptureSession()
    private let roomBuilder = RoomBuilder(options: [.beautifyObjects])
    private var finalResult: CapturedRoom?
    private var startButton: UIButton = UIButton(type: .system)
    private var stopButton: UIButton = UIButton(type: .system)
    private var exportButton: UIButton = UIButton(type: .system)
    private var infoLabel: UILabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if !RoomCaptureSession.isSupported {
            infoLabel.text = "此设备不支持LiDAR房间扫描"
            infoLabel.textColor = .white
            infoLabel.textAlignment = .center
            infoLabel.frame = view.bounds
            infoLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(infoLabel)
            return
        }
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.session = captureSession
        captureView.delegate = self
        view.addSubview(captureView)

        startButton.setTitle("开始扫描", for: .normal)
        stopButton.setTitle("停止扫描", for: .normal)
        exportButton.setTitle("导出模型", for: .normal)
        exportButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [startButton, stopButton, exportButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            stack.heightAnchor.constraint(equalToConstant: 50)
        ])

        startButton.addTarget(self, action: #selector(startScan), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopScan), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportResult), for: .touchUpInside)
    }

    @objc private func startScan() {
        finalResult = nil
        exportButton.isHidden = true
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }

    @objc private func stopScan() {
        captureSession.stop()
    }

    @objc private func exportResult() {
        guard let result = finalResult else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "RoomScan_\(formatter.string(from: Date())).usdz"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(name)
        do {
            try result.export(to: url)
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

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResult = processedResult
        exportButton.isHidden = false
    }
}
#else
class RoomScanViewController: UIViewController {
    private var infoLabel: UILabel = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        infoLabel.text = "RoomPlan不可用"
        infoLabel.textColor = .white
        infoLabel.textAlignment = .center
        infoLabel.frame = view.bounds
        infoLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(infoLabel)
    }
}
#endif
