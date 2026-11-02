import Foundation

enum LydJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let raw = keys.last!.stringValue
            let camel = raw.prefix(1).lowercased() + raw.dropFirst()
            return AnyCodingKey(stringValue: camel)!
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Match Phase A Newtonsoft defaults (PascalCase property names).
        encoder.keyEncodingStrategy = .custom { keys in
            let raw = keys.last!.stringValue
            let pascal = raw.prefix(1).uppercased() + raw.dropFirst()
            return AnyCodingKey(stringValue: pascal)!
        }
        return encoder
    }()
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
