import Foundation

public struct LaunchConfiguration {
    public var corePath: String?
    public var romPath: String?
    public var systemDirectory: String?
    public var saveDirectory: String?

    public init(corePath: String? = nil, romPath: String? = nil, systemDirectory: String? = nil, saveDirectory: String? = nil) {
        self.corePath = corePath
        self.romPath = romPath
        self.systemDirectory = systemDirectory
        self.saveDirectory = saveDirectory
    }

    public static func fromProcessArguments(_ arguments: [String] = CommandLine.arguments) -> LaunchConfiguration {
        var configuration = LaunchConfiguration()
        var iterator = arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--core":
                configuration.corePath = iterator.next()
            case "--rom":
                configuration.romPath = iterator.next()
            case "--system-dir":
                configuration.systemDirectory = iterator.next()
            case "--save-dir":
                configuration.saveDirectory = iterator.next()
            default:
                break
            }
        }

        return configuration
    }
}
