import Foundation

struct SecretsSchema: Codable {
    struct KeySpec: Codable {
        let required: Bool?
        let obfuscate: Bool?
        let description: String?
        let platforms: [String]?
    }

    let version: Int?
    let required: [String]?
    let keys: [String: KeySpec]?

    static func load(from path: String) throws -> SecretsSchema {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(SecretsSchema.self, from: data)
    }

    func requiredKeys() -> [String] {
        if let explicit = required, !explicit.isEmpty {
            return explicit
        }
        guard let keys = keys else { return [] }
        return keys.compactMap { key, spec in
            let isRequired = spec.required ?? true
            return isRequired ? key : nil
        }.sorted()
    }

    func allKeys() -> [String] {
        if let keys = keys, !keys.isEmpty {
            return Array(keys.keys).sorted()
        }
        return requiredKeys()
    }

    func shouldObfuscate(_ key: String) -> Bool {
        guard let spec = keys?[key] else { return true }
        return spec.obfuscate ?? true
    }
}
