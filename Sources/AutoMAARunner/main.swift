import AutoMAAKit
import Darwin
import Foundation

@main
enum AutoMAARunnerMain {
    @MainActor
    static func main() async {
        do {
            let configuration = try ConfigurationStore().load()
            guard let planID = requestedPlanID(), configuration.plans.contains(where: { $0.id == planID }) else {
                fputs("AutoMAA Runner: 缺少或无效的 --plan 参数\n", stderr)
                exit(EXIT_FAILURE)
            }
            let formatter = ISO8601DateFormatter()
            let runner = WorkflowRunner { event in
                print("[\(formatter.string(from: event.log.timestamp))] \(event.message)")
                fflush(stdout)
            }
            let report = await runner.run(configuration, planID: planID, resumeToday: true)
            if configuration.notifications.importantEventsEnabled {
                do {
                    try await ImportantNotificationCenter().post(
                        report: report,
                        planID: planID
                    )
                } catch {
                    fputs("AutoMAA Runner: 重要通知投递失败：\(error.localizedDescription)\n", stderr)
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
