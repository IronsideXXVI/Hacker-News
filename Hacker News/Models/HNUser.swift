import Foundation

struct HNUser: Codable {
    let id: String
    let karma: Int
    let created: Int
    let about: String?
}
