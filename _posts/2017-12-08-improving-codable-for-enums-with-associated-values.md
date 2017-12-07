---
layout: post
title: Improving Codable for enums with associated values
commentIssueId: 6
tags: codable enum
---

With Swift 4 we received a new api to help automagically encode and decode types. By conforming to `Codable` (A protocol composed of `Encodable` and `Decodable`) we can convert types to and from different formats, such as json or property lists.  

- - - -

## Quick recap
There are a number of types that already conform to `Codable` out-of-the-box. At the time of writing these are: `String`, `Int`, `Double`, `Date`, `Data` and `URL`. The nice part about `Codable` is, if your type is made up of _other_ `Codable`s then you get `Codable` for free. So that means you can define types like:
```swift
struct User: Codable {
    let name: String
    let url: URL
}
```
and
```swift
enum AuthState: String, Codable {
    case loggedIn
    case loggedOut
}
```
And `Codable` _just works_ - no extra code is required. 

You can store `AuthState` for example with something like:
```swift
let state: AuthState = .loggedIn
let data = try JSONEncoder().encode(state)
data.write(to: configFile)
```
How great is that?!

- - - -

## Limitations
The enum is interesting. The reason this works is because we have given it a `RawValue` of `String`. Swift can use that to infer a `String` for each case and since `String` is `Codable` we get it for free, but what if we wanted to change the enum slightly?
```swift
enum AuthState: Codable {
    case loggedIn(User)
    case loggedOut
}
``` 
We decide its better to store the logged in user with the logged in state and since `User` is `Codable` this should just work too right?

Unfortunately this isn’t the case (no pun intended)… the enum is no longer `RawRepresentable` and since there is _no_ `RawValue` anymore Swift doesn’t know how to encode/decode each case.

## Manually implementing Codable
To make this change work we will need to implement `Codable` ourselves. Lets start by creating the `CodingKey`s the enum will use to provide a unique key for each case:
```swift
extension AuthState {
    private enum CodingKeys: String, CodingKey {
        case loggedIn, loggedOut
    }
}
```

Next, lets implement the `Encodable` part:
```swift
extension AuthState {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .loggedIn(let user): try container.encode(user, forKey: .loggedIn)
        case .loggedOut:          try container.encode(CodingKeys.loggedOut.stringValue, forKey: .loggedOut)
        }
    }
}
```
You can see the `Encodable` part benefits from exhaustive switching, we encode cases with an associated value using their `CodingKey` as the ‘key’ and the associated value as the ‘value’. For cases without an associated value we use the `CodingKey` as both the ‘key’ and ‘value’. 

Finally lets look at the `Decodable` code:
```swift
extension AuthState {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let user = try container.decodeIfPresent(User.self, forKey: .loggedIn) {
            self = .loggedIn(user)
        } else if let _ = try container.decodeIfPresent(String.self, forKey: .loggedOut) {
            self = .loggedOut
        } else {
            throw DecodingError.valueNotFound(AuthState.self, .init(codingPath: container.codingPath, debugDescription: ""))
        }
    }
}
```
For `Decodable`  we unfortunately aren’t able to leverage exhaustive switching. So we need to attempt to decode each case one by one. For cases with an associated value this means attempting to decode the associated value for the key. For cases without associated values we attempt to decode the `String` value. Finally if nothing succeeds we throw a `DecodingError`.

This is perfectly fine and will work as-is, so we _could_ just leave it here and be done. While the `Encodable` code is about as concise as we can make it this `Decodable` code is a little wordy. 

Lets look at how we might clean this up a little.

- - - -

## Creating a reusable way to decode enums
If we look at the current solution to decoding its essentially the same as iterating through all possible cases attempting to decode the required data for each case. It stops as soon as a something is decoded, if nothing was decoded we throw an error.

Lets build something that uses that pattern:
```swift
typealias Decode<Result: Decodable, Key: CodingKey> = (KeyedDecodingContainer<Key>) throws -> Result?

func decode<Result: Decodable, Key>(using container: KeyedDecodingContainer<Key>, cases: [Decode<Result, Key>]) throws -> Result {
    guard let result = try cases.lazy.flatMap({ try $0(container) }).first
        else { throw DecodingError.valueNotFound(Result.self, .init(codingPath: container.codingPath, debugDescription: "")) }

    return result
}
```

This allows us to supply an array of closures, each one uses the container to attempt to decode the data for its specific case. Using this we end up with `Decodable` code that looks like this:
```swift
extension AuthState {
    init(from decoder: Decoder) throws {
        self = try decode(using: decoder.container(keyedBy: CodingKeys.self), cases: [
            { container in
                guard let value = try container.decodeIfPresent(User.self, forKey: .loggedIn) else { return nil }
                return .loggedIn(value)
            },
            { container in
                guard let _ = try container.decodeIfPresent(String.self, forKey: .loggedOut) else { return nil }
                return .loggedOut
            },
            ]
        )
    }
}
```
Now we have something that does the same thing as the original pattern, and while it now takes care of the error handling for us it doesn’t really read any better (in fact you could argue its actually worse 😭).

What we want to end up with is a function that fits our `Decode` signature. However because we need to provide more data we will need to create a curried function that _eventually_ returns our `Decode` function. 

The code we already have actually covers our two scenarios, so we can use them as the basis for our new curried functions.

### Without associated values
Here is our function for dealing with cases without associated values. We are passing in the case we want, assuming decoding is successful, as well as the `CodingKey` it should be stored under.

```swift
func value<Result: Decodable, Key: CodingKey>(_ case: Result, for key: Key) throws -> Decode<Result, Key> {
    return { container in
        guard let _ = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return `case`
    }
}
```

Now we can use the statement `value(AuthState.loggedOut, for: .loggedOut)` in place of the closure for this case.

### With associated values
Handling cases with associated values lets us use one of Swifts many cool features.  Cases with associated values behave like constructor functions and can be referenced the same way. An example should make this clearer:
```swift
// notice we have omitted the associated value for this case
AuthState.loggedIn // (User) -> AuthState
```

Well that is convenient, thats the exact function we need to infer all the extra details from the original closure! 
```swift
func value<Result: Decodable, Key: CodingKey, T: Decodable>(_ function: @escaping (T) -> Result, for key: Key) throws -> Decode<Result, Key> {
    return { container in
        guard let value = try container.decodeIfPresent(T.self, forKey: key) else { return nil }
        return function(value)
    }
}
```

Now our associated value closure can be replaced with `value(AuthState.loggedIn, for: .loggedIn)`.

### Final Solution
Putting it all together re can rewrite our `Decodable` code:
```swift
extension AuthState {
    init(from decoder: Decoder) throws {
        self = try decode(using: decoder.container(keyedBy: CodingKeys.self), cases: [
            value(AuthState.loggedIn, for: .loggedIn),
            value(AuthState.loggedOut, for: .loggedOut),
            ]
        )
    }
}
```

I think that looks much nicer now.

- - - -

## Caveats
It’s worth noting that while this works great for local serialization it _may_ not be in the format you need if you intend on sending this to a server. For instance our cases, when converted to json become:

`.loggedIn(User(name: "Ian Keen", url: URL(string: "http://iankeen.tech/")!))` becomes:
```json
{"loggedIn":{"name":"Ian Keen","url":"http:\/\/iankeen.tech\/"}}
```

`.loggedOut` becomes:
```json
{"loggedOut":"loggedOut"}
```

You may need to tweak the format a little to suit your server api requirements.

- - - -

## Wrapping up
Its a shame this doesn’t fit into the automagical `Codable` bucket, hopefully it is something we will get in the future. For now I think this is a decent solution for keeping this cleaner.

To see the full code checkout [here](/public/projects/improving-codable-for-enums-with-associated-values.playground) playground.
