import SwiftUI

struct ContentView: View {
    @State private var mode: Int = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("房型建模").tag(0)
                Text("点云扫描").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            Group {
                if mode == 0 {
                    RoomScanView()
                } else {
                    PointCloudScanView()
                }
            }
            .edgesIgnoringSafeArea(.all)
        }
    }
}

struct RoomScanView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RoomScanViewController {
        RoomScanViewController()
    }
    func updateUIViewController(_ uiViewController: RoomScanViewController, context: Context) {}
}

struct PointCloudScanView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PointCloudViewController {
        PointCloudViewController()
    }
    func updateUIViewController(_ uiViewController: PointCloudViewController, context: Context) {}
}
