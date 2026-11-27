import Foundation

struct CLIArguments {
    let command: String
    let options: [String: String]
    let childArguments: [String]

    init(command: String, options: [String: String], childArguments: [String] = []) {
        self.command = command
        self.options = options
        self.childArguments = childArguments
    }

    static func parse(_ argv: [String]) -> CLIArguments? {
        guard argv.count >= 2 else { return nil }
        let command = argv[1]
        var options: [String: String] = [:]
        let childSeparator = command == "exec" ? argv.dropFirst(2).firstIndex(of: "--") : nil
        let optionEnd = childSeparator ?? argv.count
        var index = 2
        while index < optionEnd {
            let token = argv[index]
            if token.hasPrefix("--") {
                let stripped = String(token.dropFirst(2))
                if let equalIndex = stripped.firstIndex(of: "=") {
                    let key = String(stripped[..<equalIndex])
                    let value = String(stripped[stripped.index(after: equalIndex)...])
                    options[key] = value
                } else if index + 1 < optionEnd, !argv[index + 1].hasPrefix("--") {
                    options[stripped] = argv[index + 1]
                    index += 1
                } else {
                    options[stripped] = "true"
                }
            }
            index += 1
        }
        let childArguments = childSeparator.map { Array(argv.dropFirst($0 + 1)) } ?? []
        return CLIArguments(command: command, options: options, childArguments: childArguments)
    }

    func option(_ key: String) -> String? {
        return options[key]
    }
}
