import AutoMAAKit
import Darwin
import Foundation

@main
enum AutoMAAResourceProbeMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 3 else {
            fputs("用法：AutoMAAResourceProbe <MaaCore 动态库> <隔离目录> <资源根目录>...\n", stderr)
            exit(EXIT_FAILURE)
        }

        do {
            try MAACoreResourceProbe.validate(
                libraryURL: URL(filePath: arguments[0]),
                userDirectory: URL(filePath: arguments[1], directoryHint: .isDirectory),
                resourceRoots: arguments.dropFirst(2).map {
                    URL(filePath: $0, directoryHint: .isDirectory)
                }
            )
            exit(EXIT_SUCCESS)
        } catch let MAACoreResourceProbeError.resourceRejected(index) {
            let root = arguments[index + 1]
            fputs("AutoMAA 资源验证失败：MaaCore 无法加载第 \(index) 层资源（\(root)/resource）\n", stderr)
            exit(EXIT_FAILURE)
        } catch {
            fputs("AutoMAA 资源验证失败：\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
