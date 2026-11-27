import AppKit
import AutoMAAKit
import SwiftUI

struct MaintenanceHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false
    @State private var updateDetails: UpdateDetailsRequest?

    private var selected: ActivitySession? {
        model.maintenanceSessions.first { $0.id == model.maintenanceHistorySelection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if selected != nil {
                    ActionIconButton(title: "返回维护记录", symbol: "chevron.left") {
                        model.maintenanceHistorySelection = nil
                    }
                }
                Text("维护记录").font(.headline)
                Spacer()
                if selected == nil, !model.maintenanceSessions.isEmpty {
                    ActionIconButton(title: "清除维护记录", symbol: "trash") { confirmsClear = true }
                        .disabled(model.isWorkflowRunning)
                }
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            if let session = selected {
                details(session)
            } else if model.maintenanceSessions.isEmpty {
                ActivityEmptyState(title: "还没有维护记录", symbol: "clock.arrow.circlepath",
                                   detail: "手动或自动更新 MAA 后，可在这里查看结果。")
            } else {
                List(model.maintenanceSessions) { session in
                    Button {
                        model.maintenanceHistorySelection = session.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(session)).lineLimit(2)
                                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isActive(session) {
                                Text("进行中").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ActivityOutcomeLabel(outcome: session.outcome).font(.caption)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 540, height: 380)
        .onExitCommand { dismiss() }
        .applicationFeedback(model, destination: .maintenanceHistory)
        .alert("清除全部维护记录？", isPresented: $confirmsClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { model.clearMaintenanceHistory() }
                .disabled(model.isWorkflowRunning)
        } message: {
            Text("将清除独立 MAA 维护的摘要与过程记录。方案运行记录和磁盘诊断日志会保留。")
        }
        .sheet(item: $updateDetails) { request in
            UpdateDetailsView(model: model, request: request)
                .focusedSceneValue(\.operationCommandScope, .unavailable)
        }
    }

    private func title(_ session: ActivitySession) -> String {
        session.updateInformation?.title ?? session.entries.first?.message ?? "MAA 维护"
    }

    private func isActive(_ session: ActivitySession) -> Bool {
        model.isMAAMaintenanceRunning && session.runID != nil && model.activeRunID == session.runID
    }

    private func details(_ session: ActivitySession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title(session)).font(.headline)
                HStack {
                    Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                        .foregroundStyle(.secondary)
                    if isActive(session) {
                        Text("进行中")
                        Button("取消更新") { model.cancelRun() }.disabled(!model.canCancelRun)
                    } else {
                        ActivityOutcomeLabel(outcome: session.outcome)
                    }
                }
                .font(.caption)
                HStack(spacing: 14) {
                    if let information = session.updateInformation {
                        ActionTextButton(title: "更新内容", symbol: "doc.text", help: "查看本次维护的更新内容") {
                            updateDetails = .maa(information)
                        }
                    }
                    if let runID = session.runID {
                        let url = DiagnosticLogStore(directories: model.directories).url(for: runID)
                        if FileManager.default.fileExists(atPath: url.path) {
                            ActionTextButton(title: "诊断日志", symbol: "doc.text.magnifyingglass",
                                             help: "在访达中显示本次维护的诊断日志") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    }
                }
                ActivityLogRows(entries: session.entries, showsContext: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
