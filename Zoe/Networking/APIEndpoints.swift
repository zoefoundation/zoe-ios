import Foundation

enum APIEndpoints {
    // TODO: move to Info.plist / build settings for per-environment configuration
    static let baseURL: URL = {
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "ZOE_API_BASE_URL") as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Compile-time fallback
        return URL(string: "https://api.zoe.media")!
    }()

    static let challengePath = "/v1/challenge"
    static let registerPath = "/v1/keys/register"

    static func url(for path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }
}
