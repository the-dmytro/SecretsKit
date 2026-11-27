import Foundation

struct SecretsKitConfigFile: Decodable {
    struct AutoConfig: Decodable {
        let order: [String]?
        let allowMerge: Bool?
    }

    struct FileConfig: Decodable {
        let sourcePath: String?
    }

    struct VaultConfig: Decodable {
        let backend: String?
        let references: [String: String]?
        let addr: String?
        let addrEnv: String?
        let tokenEnv: String?
        let namespaceEnv: String?
        let mount: String?
        let mountEnv: String?
        let path: String?
        let pathEnv: String?
        let kvVersion: Int?
        let timeoutSeconds: Double?
    }

    let schemaPath: String?
    let provider: String?
    let auto: AutoConfig?
    let file: FileConfig?
    let vault: VaultConfig?
}

struct SecretsKitConfig {
    let file: SecretsKitConfigFile
    let baseURL: URL

    static func load(from path: String) throws -> SecretsKitConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(SecretsKitConfigFile.self, from: data)
        return SecretsKitConfig(file: file, baseURL: url.deletingLastPathComponent())
    }

    func resolvePath(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.hasPrefix("~") {
            return (value as NSString).expandingTildeInPath
        }
        if value.hasPrefix("/") {
            return value
        }
        return baseURL.appendingPathComponent(value).path
    }

    var schemaPath: String? { resolvePath(file.schemaPath) }
    var fileSourcePath: String? { resolvePath(file.file?.sourcePath) }
}
