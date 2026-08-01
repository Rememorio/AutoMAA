import AutoMAAKit
import Darwin
import Foundation

@main
enum AutoMAARunnerMain {
    @MainActor
    static func main() async {
        do {
            let configuration = try ConfigurationStore().load()
            let formatter = ISO8601DateFormatter()
            let runner = WorkflowRunner { event in
                print("[\(formatter.string(from: event.log.timestamp))] \(event.message)")
                fflush(stdout)
            }
            let report = await runner.run(configuration, resumeToday: true)
            exit(report.isSuccess ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            fputs("AutoMAA Runner: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
