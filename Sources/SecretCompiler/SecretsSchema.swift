import Foundation

/// How a key may be handled at build time.
///
/// - `public`: safe to ship as-is (e.g. a published client id). Bundled, not obfuscated by default.
/// - `clientBundled` (local-only): lives only on the device; accepts eventual disclosure. Bundled and
///   obfuscated. This is the default when a key declares no classification.
/// - `serverOnly`: a real secret that must never reach a device. Never bundled; `seal` excludes it and
///   refuses if it is explicitly routed into the bundle.
enum SecretClassification: String, Codable {
    case `public`
    case clientBundled
    case serverOnly
}

struct SecretsSchema: Codable {
    struct KeySpec: Codable {
        let required: Bool?
        let obfuscate: Bool?
        let description: String?
        let platforms: [String]?
        let classification: String?
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

    /// The raw `classification` string declared for a key, if any. Validated/parsed by the caller.
    func rawClassification(for key: String) -> String? {
        return keys?[key]?.classification
    }

    func shouldObfuscate(_ key: String) -> Bool {
        let spec = keys?[key]
        // Public values ship as-is unless explicitly overridden; everything else obfuscates by default.
        if rawClassification(for: key) == SecretClassification.public.rawValue {
            return spec?.obfuscate ?? false
        }
        return spec?.obfuscate ?? true
    }
}
