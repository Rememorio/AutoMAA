import AppKit
import AutoMAAKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct MobileAccessView: View {
    @ObservedObject var controller: MobileAccessController
    @State private var showsPairing = false
    @State private var revoking: MobileDevice?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "手机连接", symbol: "iphone.gen3.radiowaves.left.and.right", detail: "允许已配对手机查看状态、运行方案和安全停止。")
                SettingsToggleRow(title: "允许手机连接", detail: "Mac 和手机需连接同一 Tailscale 网络；退出 AutoMAA 或 Mac 睡眠后不可访问。",
                                  isOn: Binding(get: { controller.enabled }, set: controller.setEnabled))
                if controller.connecting {
                    HStack { ProgressView().controlSize(.small); Text("正在建立安全连接…") }
                } else if let endpoint = controller.endpoint {
                    Label("手机连接已就绪", systemImage: "checkmark.shield").foregroundStyle(.green)
                    Text(endpoint).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Button { controller.beginPairing(); showsPairing = controller.pairing != nil } label: {
                        Label("配对手机", systemImage: "qrcode")
                    }
                }
                if let error = controller.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if controller.enabled && !controller.connecting { Button("重试连接", action: controller.start) }
                        Link("Tailscale 设置说明", destination: URL(string: "https://tailscale.com/docs/features/tailscale-serve")!)
                        Link("安装 Tailscale", destination: URL(string: "https://tailscale.com/download/mac")!)
                    }
                }
                if !controller.devices.isEmpty {
                    Divider()
                    Text("已授权手机").font(.subheadline.weight(.semibold))
                    ForEach(controller.devices) { device in
                        HStack {
                            Label(device.name, systemImage: "iphone")
                            Spacer()
                            Button(role: .destructive) { revoking = device } label: { Image(systemName: "trash") }
                                .help("撤销 \(device.name) 的授权").accessibilityLabel("撤销 \(device.name) 的授权")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsPairing, onDismiss: controller.cancelPairing) {
            pairingSheet
        }
        .confirmationDialog("撤销手机授权？", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button("撤销授权", role: .destructive) { if let device = revoking { controller.revoke(device) }; revoking = nil }
            Button("取消", role: .cancel) { revoking = nil }
        } message: { Text("\(revoking?.name ?? "该手机") 会立即断开，需要重新配对才能访问。正在运行的任务不受影响。") }
    }

    private var pairingSheet: some View {
        VStack(spacing: 18) {
            Text("配对手机").font(.title2.weight(.semibold))
            if let code = controller.pairing,
               let data = try? MobileProtocol.encode(code) {
                if let qr = qrImage(data) {
                    Image(nsImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 240, height: 240).padding(12).background(.white)
                        .accessibilityLabel("手机配对二维码")
                }
                Text("有效至 \(code.expiresAt.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                } label: { Label("复制配对信息", systemImage: "doc.on.doc") }
                if let approval = controller.approval {
                    Divider()
                    Text("允许“\(approval.name)”查看和控制 AutoMAA？").font(.headline)
                    Text("授权后可运行已有方案和安全停止，不能修改配置。").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("拒绝", role: .cancel) { controller.cancelPairing(); showsPairing = false }
                        Button("允许连接") { controller.approve(); if controller.pairing == nil { showsPairing = false } }
                            .buttonStyle(.borderedProminent).tint(.maaAction)
                    }
                } else { Text("请在手机扫码，随后在这里确认授权。").font(.callout).foregroundStyle(.secondary) }
            } else {
                Text("配对信息已过期或已使用")
                Button("重新生成", action: controller.beginPairing)
            }
            Button("关闭", role: .cancel) { showsPairing = false }
        }
        .padding(28).frame(width: 430)
    }

    private func qrImage(_ data: Data) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: output.extent.size)
    }
}
