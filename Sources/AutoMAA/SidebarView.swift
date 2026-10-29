import AppKit
import AutoMAAKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandLogo().frame(width: 32, height: 32)
                Text("AutoMAA").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
            List(selection: $model.selection) {
                Label("今日总览", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.overview)
                Section {
                    planHeader
                        .selectionDisabled()
                        .listRowBackground(Color.clear)
                    ForEach(model.configuration.plans) { plan in
                        HStack(spacing: 8) {
                            Image(systemName: "checklist").foregroundStyle(Color.maaAccent)
                                .accessibilityHidden(true)
                            Text(plan.displayName).lineLimit(1).help(plan.displayName)
                            Spacer(minLength: 2)
                            if plan.schedule.enabled {
                                Image(systemName: model.isPlanScheduleCurrent(plan) ? "clock" : "clock.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundStyle(model.isPlanScheduleCurrent(plan) ? Color.secondary : .orange)
                                    .help(PlanScheduleFormatter.summary(plan.schedule))
                            }
                        }
                        .tag(SidebarSelection.plan(plan.id))
                    }
                }
                Section {
                    Label("客户端与账号", systemImage: "desktopcomputer")
                        .tag(SidebarSelection.clients)
                    Label("运行记录", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarSelection.activity)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            footer
        }
    }

    private var planHeader: some View {
        HStack {
            Text("自动化方案")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button("轻量日常") { model.addPlan(.lightRoutine) }
                Button("完整日常") { model.addPlan(.completeRoutine) }
                Divider()
                Button("空白方案") {
                    var plan = AutomationPlan(name: "新方案")
                    plan.fight.enabled = false
                    plan.recruit.enabled = false
                    plan.infrast.enabled = false
                    plan.mall.enabled = false
                    plan.award.enabled = false
                    model.addPlan(plan)
                }
            } label: {
                Image(systemName: "plus").frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(model.isWorkflowRunning)
            .help("添加自动化方案").accessibilityLabel("添加自动化方案")
        }
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.horizontal, 8).padding(.bottom, 6)
            footerButton("帮助与公告", symbol: "questionmark.circle") {
                NSWorkspace.shared.open(model.documentationURL)
            }
            footerButton("查找日志", symbol: "doc.text.magnifyingglass") {
                NSWorkspace.shared.open(model.directories.logs)
            }
            footerButton("设置", symbol: "gearshape") { model.showSettings() }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

    private func footerLabel(_ title: String, symbol: String) -> some View {
        SidebarUtilityLabel(title: title, symbol: symbol)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { footerLabel(title, symbol: symbol) }
            .buttonStyle(.plain).help(title)
    }
}

private struct SidebarUtilityLabel: View {
    let title: String
    let symbol: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(nsColor: isHovered ? .labelColor : .secondaryLabelColor))
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
