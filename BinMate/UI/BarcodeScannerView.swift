import SwiftUI

#if !targetEnvironment(macCatalyst)
import VisionKit

/// Live barcode scanning, wrapped from VisionKit.
///
/// `DataScannerViewController` is unavailable on the simulator, on Mac Catalyst, and on
/// devices without a Neural Engine, so every caller must be able to cope without it.
/// `ScannerSheet` below is the only thing the app presents, and it always offers a way
/// forward.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    static var isUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .itf14])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !context.coordinator.isScanning else { return }
        context.coordinator.isScanning = true
        try? controller.startScanning()
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        coordinator.isScanning = false
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var isScanning = false
        /// A barcode in frame is recognised many times a second. Without this the
        /// lookup would fire repeatedly for one physical product.
        private var hasDelivered = false
        private let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(from: addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliver(from: [item])
        }

        private func deliver(from items: [RecognizedItem]) {
            guard !hasDelivered else { return }
            for case .barcode(let barcode) in items {
                guard let payload = barcode.payloadStringValue,
                      !payload.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                hasDelivered = true
                onScan(payload)
                return
            }
        }
    }
}

#endif

/// What the app actually presents: the camera when it is available, and an honest
/// explanation plus a manual route when it is not.
struct ScannerSheet: View {
    var onBarcode: (String) -> Void
    var onManual: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typedBarcode = ""

    /// Mac Catalyst has no `DataScannerViewController` at all, so the check is a compile
    /// time one there rather than a runtime capability query.
    private var cameraIsUsable: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        BarcodeScannerView.isUsable
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if cameraIsUsable {
                    cameraScanner
                } else {
                    unavailableScanner
                }
            }
            .navigationTitle("Scan a barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var cameraScanner: some View {
        #if !targetEnvironment(macCatalyst)
        BarcodeScannerView { payload in
            onBarcode(payload)
            dismiss()
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                Text("Point the camera at the barcode")
                    .font(.subheadline.weight(.medium))
                Button("Enter it by hand instead") {
                    dismiss()
                    onManual()
                }
                .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        #endif
    }

    private var unavailableScanner: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label("Camera scanning unavailable", systemImage: "camera.metering.unknown")
            } description: {
                Text("Live scanning needs a physical iPhone or iPad. Everything else — the sorting rules, the sample products, your history — works here.")
            }

            VStack(spacing: 12) {
                TextField("Barcode digits", text: $typedBarcode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .font(.body.monospacedDigit())

                Button {
                    let trimmed = typedBarcode.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onBarcode(trimmed)
                    dismiss()
                } label: {
                    Text("Look it up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(typedBarcode.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Describe the packaging instead") {
                    dismiss()
                    onManual()
                }
                .font(.footnote)
            }
            .padding()
        }
    }
}
