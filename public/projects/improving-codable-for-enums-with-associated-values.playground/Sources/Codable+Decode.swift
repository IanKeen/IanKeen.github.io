import Foundation

public typealias Decode<Result: Decodable, Key: CodingKey> = (KeyedDecodingContainer<Key>) throws -> Result?

public func decode<Result: Decodable, Key>(using container: KeyedDecodingContainer<Key>, cases: [Decode<Result, Key>]) throws -> Result {
    guard let result = try cases.lazy.flatMap({ try $0(container) }).first
        else { throw DecodingError.valueNotFound(Result.self, .init(codingPath: container.codingPath, debugDescription: "")) }

    return result
}

public func value<Result: Decodable, Key: CodingKey>(_ case: Result, for key: Key) throws -> Decode<Result, Key> {
    return { container in
        guard let _ = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return `case`
    }
}
public func value<Result: Decodable, Key: CodingKey, T: Decodable>(_ function: @escaping (T) -> Result, for key: Key) throws -> Decode<Result, Key> {
    return { container in
        guard let value = try container.decodeIfPresent(T.self, forKey: key) else { return nil }
        return function(value)
    }
}
