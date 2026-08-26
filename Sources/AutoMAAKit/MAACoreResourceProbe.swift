import Darwin
import Foundation

public enum MAACoreResourceProbeError: LocalizedError {
    case libraryUnavailable
    case libraryLoadFailed(String)
    case symbolUnavailable(String)
    case userDirectoryRejected
    case resourceRejected(Int)
    case assistantCreationRejected

    public var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            "MaaCore 动态库不存在或不可读取"
        case let .libraryLoadFailed(details):
            "无法载入 MaaCore 动态库：\(details)"
        case let .symbolUnavailable(symbol):
            "MaaCore 缺少资源验证接口：\(symbol)"
        case .userDirectoryRejected:
            "MaaCore 拒绝使用隔离的验证目录"
        case let .resourceRejected(index):
            "MaaCore 无法加载第 \(index) 层资源"
        case .assistantCreationRejected:
            "MaaCore 加载资源后无法完成初始化"
        }
    }
}

public enum MAACoreResourceProbe {
    private typealias AsstPathFunction = @convention(c) (UnsafePointer<CChar>) -> UInt8
    private typealias AsstCreateFunction = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias AsstDestroyFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void

    public static func validate(
        libraryURL: URL,
        userDirectory: URL,
        resourceRoots: [URL]
    ) throws {
        guard FileManager.default.isReadableFile(atPath: libraryURL.path) else {
            throw MAACoreResourceProbeError.libraryUnavailable
        }
        try FileManager.default.createDirectory(
            at: userDirectory,
            withIntermediateDirectories: true
        )

        guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw MAACoreResourceProbeError.libraryLoadFailed(dynamicLoaderError())
        }
        defer { dlclose(handle) }

        let setUserDirectory: AsstPathFunction = try function(
            named: "AsstSetUserDir",
            in: handle
        )
        let loadResource: AsstPathFunction = try function(
            named: "AsstLoadResource",
            in: handle
        )
        let createAssistant: AsstCreateFunction = try function(named: "AsstCreate", in: handle)
        let destroyAssistant: AsstDestroyFunction = try function(named: "AsstDestroy", in: handle)

        guard userDirectory.path.withCString({ setUserDirectory($0) }) != 0 else {
            throw MAACoreResourceProbeError.userDirectoryRejected
        }
        for (offset, root) in resourceRoots.enumerated() {
            guard root.path.withCString({ loadResource($0) }) != 0 else {
                throw MAACoreResourceProbeError.resourceRejected(offset + 1)
            }
        }
        guard let assistant = createAssistant() else {
            throw MAACoreResourceProbeError.assistantCreationRejected
        }
        destroyAssistant(assistant)
    }

    private static func function<T>(named name: String, in handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw MAACoreResourceProbeError.symbolUnavailable(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func dynamicLoaderError() -> String {
        guard let error = dlerror() else { return "未知动态加载错误" }
        return String(cString: error)
    }
}
