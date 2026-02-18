import Foundation

struct AppUser {
    let uid: String
    let email: String?
    let displayName: String?
    let photoURL: URL?

    var initials: String {
        guard let name = displayName, !name.isEmpty else {
            return email?.prefix(1).uppercased() ?? "?"
        }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

struct AuthTokenResponse: Codable {
    let token: String
    let user: AuthUserInfo
}

struct AuthUserInfo: Codable {
    let id: String
    let username: String
    let role: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case role
        case displayName = "display_name"
    }
}
