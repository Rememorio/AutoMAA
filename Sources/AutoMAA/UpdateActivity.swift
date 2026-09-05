import AutoMAAKit
import Foundation

struct MAAUpdateActivity {
    let component: MAAComponentUpdate
    let automatic: Bool
    let startedAt = Date()
    var phase: RunnerPhase = .preparing
    var message = "正在准备更新"
    var details: String?
    var isCancelling = false

    var isFinished: Bool {
        switch phase {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }
}
