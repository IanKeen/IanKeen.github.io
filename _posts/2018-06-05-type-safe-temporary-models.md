---
layout: post
title: Type safe temporary models
commentIssueId: 7
tags: generics keypath
---

Recently I had to build a system to onboard users. This meant collecting different pieces of information over a number of screens. We are also utilizing A/B testing which means not only can the order of screens change, but certain pieces of information may be collected by a single screen or broken up across many.

The data I want to end up with looks something like:

```swift
struct User {
    let firstName: String
    let lastName: String
    let age: Int?
}
```

There are multiple ways to go about collecting this data, I could simply give each screen an optional property:

```swift
class FirstNameViewController: UIViewController {
    private var firstName: String?
    
    // ...
}
```

This would get the job done, but there are a few problems to overcome...

- What about the A/B testing? We would very quickly end up with our screens having a number of the same optional properties. 
- How do we keep track of and consolidate all of these properties at the end?

An alternate approach would be to have a second version of our model with optional properties, such as:

```swift
struct PartialUser {
    let firstName: String?
    let lastName: String?
    let age: Int?
}
```

This is an improvement, we now have all the pieces in one place. We can create a `User.init` that accepts this model to produce a complete `User` instance for us:

```swift
extension User {
    init(from partial: PartialUser) {
        // ...
    }
}
```

However it comes with it own set of problems... 

- We have to keep it in sync with the 'real' model
- This `init` can look a little messy having to deal with both required and optional properties
- What do we do when a required value is missing?

It's worth noting that neither of these solution scale well for other uses, there is a lot of associated boilerplate that we would need to repliacate for each specific use case.

We could try to solve the scaling problem with a `Dictionary`... what about using `[String: Any]`? While this scales fine it's a step backwards in safety.

`String` keys are problematic, they are prone to typos and will easily fall out of sync. We could look at using a `String` enum but then we've re-introduced our scaling issue again!

On the value side `Any` strips all our type information and we would then have to cast values back top the desired types again anyway.

What we need is something that combines the last two attempts. It should scale like a dictionary but gives us the type safety of an explicit model.

---

Lets stick with the `Dictionary` for now. Can we improve on `String` keys? Turns out Swift `KeyPath`s are a great solution to this!

```swift
var partialUser: [PartialKeyPath<User>: Any] = [:]
```

By using a `PartialKeyPath` we are able to restrict the keys to _only_ properties on `User` like so:

```swift
partialUser[\User.firstName] = "Ian"
```

This is great! Now if our `User` model changes this dictionary will scale perfectly with it. New properties will be available as they are added and changes to existing properties will cause the compiler to complain.

What about the pesky `Any`? Right now you could replace the `String` value `"Ian"` with something like an `Int` of `42` and it would still compile (though it will fail when you try and extract it). Is there a different type we can use here to fix that? 

Sadly no...

But there is hope! Let's build a new type that will solve this problem _and_ make this solution more _generic_ (pun intended 😄)

---

## Partial\<T>

Let's start by putting in the `KeyPath` based `Dictionary` we have already to keep track of our changes:

```swift
struct Partial<T> {
    private var data: [PartialKeyPath<T>: Any] = [:]
    
    //...
}
```

This gives us a generic type that we can now use with _any_ type we want:

```swift
var partial = Partial<User>()
``` 

Next, we can use a generic function to ensure the dictionary is updated with the correct types:

```swift
    mutating func update<U>(_ keyPath: KeyPath<T, U>, to newValue: U?) {
        data[keyPath] = newValue
    }
```

We use a _full_ `KeyPath` here so we can gain access to the generic type of the value of the property. This works because `KeyPath` is a subclass of `PartialKeyPath`. With this function we can now update the data using:

```swift
partial.update(\.firstName, to: "Ian")
```

And because we now have access to the properties type we can restrict the value being set. For instance we can no longer pass `42`. It's also worth noting that we can pass `nil` to erase any stored value too! We now have a type safe, scalable, setter!

We can use these same features to also build out the getter:

```swift
    func value<U>(for keyPath: KeyPath<T, U>) throws -> U {
        guard let value = data[keyPath] as? U else { throw Error.valueNotFound }
        return value
    }
    func value<U>(for keyPath: KeyPath<T, U?>) -> U? {
        return data[keyPath] as? U
    }
```

Here we are encapsulating the casting of `Any` to the desired type and adding error handling. We also add in an overload to allow us to deal with optionals in a consistent way.

---

## Putting it all together

This is what our full `Partial<T>` looks like:

```swift
struct Partial<T> {
    enum Error: Swift.Error {
        case valueNotFound
    }
    
    private var data: [PartialKeyPath<T>: Any] = [:]
    
    mutating func update<U>(_ keyPath: KeyPath<T, U>, to newValue: U?) {
        data[keyPath] = newValue
    }
    func value<U>(for keyPath: KeyPath<T, U>) throws -> U {
        guard let value = data[keyPath] as? U else { throw Error.valueNotFound }
        return value
    }
    func value<U>(for keyPath: KeyPath<T, U?>) -> U? {
        return data[keyPath] as? U
    }
}
```

And we can now extend our original `User` model like so:

```swift
extension User {
    init(from partial: Partial<User>) throws {
        self.firstName = try partial.value(for: \.firstName)
        self.lastName = try partial.value(for: \.lastName)
        self.age = partial.value(for: \.age)
    }
}
```

---

## Wrapping up

Sadly we are not able to provide a default implementation for the convenience `init` _yet_. I've explored a few ways of getting this to work however the core issue is that there is, currently, no way of converting to or from `KeyPath`s to other types.

It's a shame but regardless, I think this is an interesting use of `KeyPath`s. I also like the feel of this solution when compared to the other attempts because of the ability to exactly mirror the underlying model and the resulting compiler safety.

Let me know what you think!
