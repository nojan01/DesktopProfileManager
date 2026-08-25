import Foundation

/// Lädt Release-Informationen und signierte DMG-Updates von GitHub herunter.
enum UpdateManager {
    struct Release: Equatable {
        let version: String
        let downloadURL: URL?
        let assetName: String?
    }

    enum UpdateError: LocalizedError {
        case invalidURL
        case invalidResponse
        case unexpectedStatus(Int)
        case invalidRelease
        case missingDMG

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Ungültige Update-Adresse."
            case .invalidResponse: return "Ungültige Antwort vom Update-Server."
            case .unexpectedStatus(let status): return "Update-Server antwortete mit Status \(status)."
            case .invalidRelease: return "Die Release-Informationen sind unvollständig."
            case .missingDMG: return "Dieses Release enthält keine DMG-Datei."
            }
        }
    }

    static func fetchLatest(repo: String, completion: @escaping (Result<Release, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(.failure(UpdateError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DesktopProfileManager", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(UpdateError.invalidResponse))
                return
            }
            guard (200..<300).contains(response.statusCode) else {
                completion(.failure(UpdateError.unexpectedStatus(response.statusCode)))
                return
            }
            guard let data, let release = release(from: data) else {
                completion(.failure(UpdateError.invalidRelease))
                return
            }
            completion(.success(release))
        }.resume()
    }

    /// Liest Version und die erste DMG-Datei aus der GitHub-Release-Antwort.
    static func release(from data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else {
            return nil
        }
        let version = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard !version.isEmpty else { return nil }

        let assets = object["assets"] as? [[String: Any]] ?? []
        let dmgAsset = assets.first { asset in
            guard let name = asset["name"] as? String,
                  let download = asset["browser_download_url"] as? String,
                  let url = URL(string: download) else { return false }
            return name.lowercased().hasSuffix(".dmg") && url.scheme?.lowercased() == "https"
        }
        let name = dmgAsset?["name"] as? String
        let url = (dmgAsset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return Release(version: version, downloadURL: url, assetName: name)
    }

    static func downloadDMG(_ release: Release, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let source = release.downloadURL, let originalName = release.assetName else {
            completion(.failure(UpdateError.missingDMG))
            return
        }
        let fileName = (originalName as NSString).lastPathComponent
        guard fileName.lowercased().hasSuffix(".dmg"), !fileName.isEmpty else {
            completion(.failure(UpdateError.missingDMG))
            return
        }

        URLSession.shared.downloadTask(with: source) { temporaryURL, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let temporaryURL else {
                completion(.failure(UpdateError.invalidResponse))
                return
            }
            do {
                let manager = FileManager.default
                let downloads = manager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                try manager.createDirectory(at: downloads, withIntermediateDirectories: true)
                let destination = availableDownloadURL(named: fileName, in: downloads, fileManager: manager)
                try manager.moveItem(at: temporaryURL, to: destination)
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    static func availableDownloadURL(named fileName: String, in directory: URL,
                                     fileManager: FileManager = .default) -> URL {
        let original = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 2
        while true {
            let candidateName = "\(base) (\(counter)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
