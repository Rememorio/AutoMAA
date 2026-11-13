enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case environment
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .environment: "MAA 环境"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .environment: "cpu"
        case .about: "info.circle"
        }
    }
}
