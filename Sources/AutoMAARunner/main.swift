import AutoMAAKit
import Darwin
import Foundation

@main
enum AutoMAARunnerMain {
    @MainActor
    static func main() async {
        let notificationCenter = ImportantNotificationCenter()
        if CommandLine.arguments.contains("--test-notification") {
            let result = await notificationCenter.postTestNotification()
            if result.wasDelivered {
                print("AutoMAA Runner: 后台测试通知已发送")
                exit(EXIT_SUCCESS)
            }
            fputs("AutoMAA Runner: \(result.failureDescription ?? "后台测试通知未送达")\n", stderr)
            exit(EXIT_FAILURE)
        }

        do {
            let configuration = try ConfigurationStore().load()
            guard let planID = requestedPlanID(), configuration.plans.contains(where: { $0.id == planID }) else {
                fputs("AutoMAA Runner: 缺少或无效的 --plan 参数\n", stderr)
                exit(EXIT_FAILURE)
            }
            let formatter = ISO8601DateFormatter()
            var runID: UUID?
            let noticeSink: WorkflowRunner.NoticeSink?
            if configuration.notifications.importantEventsEnabled {
                noticeSink = { @MainActor @Sendable notices, planID in
                    await notificationCenter.post(notices: notices, planID: planID)
                }
            } else {
                noticeSink = nil
            }
            let runner = WorkflowRunner(noticeSink: noticeSink) { event in
                runID = event.log.runID
                print("[\(formatter.string(from: event.log.timestamp))] \(event.message)")
                fflush(stdout)
            }
            let report = await runner.run(configuration, planID: planID, resumeToday: true)
            if configuration.notifications.importantEventsEnabled {
                let result = await notificationCenter.post(report: report, planID: planID)
                if let failure = result.failureDescription {
                    let message = "重要通知未送达：\(failure)"
                    HistoryStore().append(LogEntry(
                        level: .warning,
                        message: message,
                        runID: runID,
                        phase: .completed,
                        progress: 1,
                        planID: planID
                    ))
                    fputs("AutoMAA Runner: \(message)\n", stderr)
                }
            }
            exit(report.isSuccess ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            fputs("AutoMAA Runner: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func requestedPlanID() -> UUID? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--plan"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return UUID(uuidString: arguments[index + 1])
    }
}
