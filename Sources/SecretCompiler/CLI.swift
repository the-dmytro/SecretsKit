import Foundation

struct CLIArguments {
    let command: String
    let options: [String: String]

    static func parse(_ argv: [String]) -> CLIArguments? {
        guard argv.count >= 2 else { return nil }
        let command = argv[1]
        var options: [String: String] = [:]
        var index = 2
        while index < argv.count {
            let token = argv[index]
            if token.hasPrefix("--") {
                let stripped = String(token.dropFirst(2))
                if let equalIndex = stripped.firstIndex(of: "=") {
                    let key = String(stripped[..<equalIndex])
                    let value = String(stripped[stripped.index(after: equalIndex)...])
                    options[key] = value
                } else if index + 1 < argv.count, !argv[index + 1].hasPrefix("--") {
                    options[stripped] = argv[index + 1]
                    index += 1
                } else {
                    options[stripped] = "true"
                }
            }
            index += 1
        }
        return CLIArguments(command: command, options: options)
    }

    func option(_ key: String) -> String? {
        return options[key]
    }
}
