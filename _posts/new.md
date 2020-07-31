---
layout: post
title: ...
commentIssueId: x
tags: combine, mvvm, propertywrapper
---

# The missing Combine Input type

Like most people I have been tinkering with SwiftUI and Combine lately. Mostly using the MVVM pattern since that's what I know best. 
One thing I miss from RxSwift that Combine doesn't seem to have is a dedicated _input only_ type. 
In RxSwift there is a protocol called `Observer` with a provided concrete type of `AnyObserver<T>`. 
An `Observer` only exposes ways to send values _in_ but not subscribe to those changes elsewhere.

So... why would this be useful? Well I'm a bit of a stickler for encapsulation. 
When I'm building, but more importantly debugging, my view models I like to know how data is flowing through them. 
With strict separation between inputs and outputs I know that any side effects are _only_ triggered as a result of values coming out of the outputs. 
Likewise I also know that the only thing that could trigger those outputs are the _inputs_ and reacting to the inputs is _only_ able to happen 
from within the view model. This separation makes reasoning about the flow of data _much_ easier, at least for me.

To dig into this concept, let's take a look at an example view model for authenticating a user:

```swift
class AuthViewModel {
    // MARK: - Outputs
    //..
    
    // MARK: - Lifecycle
    init() {
        //...
    }
}
```

## Outputs

To represent outputs Combine gives us a `Publisher` type. We can subscribe to them and use them to make our apps do things. 
At the end of a `Publisher` you will eventually find one or more `.sink { ... }` calls, these are where our side effects live. 
This includes things like updating the UI or saving information to a database.

Let's add an output we can use to perform a side effect based on the success or failure of an authentication attempt

```swift
class AuthViewModel {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Lifecycle
    init() {
        //...
    }
}
```

Here we have `signInResult` using the `Result` type as its output. When authentication is successful it will emit a `.success(Token)` value, 
when it fails it will output a `.failure(Error)` value.

So how do we go about _triggering_ the work and eventually get a value from this output? We need an input!

## Inputs... ?

But didn't we already decide Combine doesn't have any input types? It _does_ have ways to model inputs... they just come with some baggage.

The type Combine gives us to send values are called `Subject`s. _But_, they are _both_ input _and_ output (`Publisher`). 
This means that while we can use them to trigger our authentication attempt we need to be careful about how we use them if we care about encapsulation.

Let's introduce a `Subject` and get our view model actually doing something:

```swift
class AuthViewModel {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Inputs
    let signIn = PassthroughSubject<(username: String, password: String), Never>()

    // MARK: - Lifecycle
    init() {
        signInResult = signIn
            .flatMap { input in
                return API
                    .authenticate(input.username, input.password)
                    .materialize()
            }
            .eraseToAnyPublisher()
    }
}
```

Now we have defined an input we can use it to attempt to authenticate and, finally, emit the result through our output like so:

```swift
let viewModel = AuthViewModel()

viewModel.signInResult
    .sink { result in
        print(result) // success(Token(value: "foobar"))
    }
    .store(in: &cancellables)

viewModel.signIn.send((username: "iankeen", password: "super_secret_password"))
```

Not bad..., however remember `Subject`s are both input _and_ output. This means we have also left the door open for code like this:

```swift
viewModel.signIn
    .sink { result in
        somethingUnexpected(with: result)
    }
    .store(in: &cancellables)
```

Since `Subject`s can be subscribed to there could be hard to track down side effects outside the control of our view model. 
Let's take a look at a simple approach to get our encapsulation back!:

```swift
class AuthViewModel {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Inputs
    private let signIn = PassthroughSubject<(username: String, password: String), Never>()

    // MARK: - Lifecycle
    init() {
        signInResult = signIn
            .flatMap { input in
                return API
                    .authenticate(input.username, input.password)
                    .materialize()
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Public Functions
    func signIn(username: String, password: String) {
        signIn.send((username, password))
    }
}
```

Much better! We now have closed off the ability for unintended side effects by giving `signIn` a `private` access level. 
Consumers of the view model can now use the `signIn(username:password:)` function to perform an authentication attempt.

Now we could stop here and it would be perfectly fine, but having to maintain a `Subject` _and_ a function bothers me just 
enough to potentially over-engineer an alternative... strap yourself in.

## Inputs!... for real this time

What we want is a type that exposes a way to _send_ values publicly, but _derive_ streams using them internally. 
My first thought was to try using PropertyWrappers since we can take advantage of the `_value` syntax to gain the encapsulation we want:

```swift
@propertyWrapper
struct Input<Parameters> {
    struct SendProxy {
        let send: (Parameters) -> Void
    }

    var wrappedValue: Parameters { fatalError("Send values via the $projectedValue") }
    var projectedValue: SendProxy { .init(send: subject.send) }

    init() { }

    let subject = PassthroughSubject<Parameters, Never>()
}
```

There's a fair bit going on in this little snippet so let's unpack it quickly...

The reason I first thought PropertyWrappers might be a good solution is because they allow us to expose things differently. 
We can use the publicly visible members (`wrappedValue` and `projectedValue`) to expose the parameters for the input and a way to send them. 
We can them use the restricted members (the `_underscore` accessor) to give the enclosing type exclusive access to the `Subject`.

We don't really want the `wrappedValue` here, it's just a means to expose a generic parameter. 
The `projectedValue` exposes a `SendProxy` which is just a way for use to provide _only_ the `send` function to code outside the view model.

Clear as mud? Let's take a look at how we might use this in our view model and hopefully it'll make sense:

```swift
class AuthViewModel {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Inputs
    @Input var signIn: (username: String, password: String)

    // MARK: - Lifecycle
    init() {
        signInResult = _signIn // underscore accessor let's us use the `Subject` exclusively
            .subject
            .flatMap { input in
                return API
                    .authenticate(input.username, input.password)
                    .materialize()
            }
            .eraseToAnyPublisher()
    }
}
```

We can now sue the following syntax to send values:

```swift
viewModel.$signIn.send((username: "...", password: "..."))
```

The PropertyWrapper itself is a little crazy, but the view model and the call site is a little cleaner I think. 
Unfortunately there is actually a pretty big downside to this approach, PropertyWrappers can't be enforced in protocols.

Consider this:

```swift
protocol AuthViewModelType {
    // MARK: - Outputs
    var signInResult: AnyPublisher<Result<Token, Error>, Never> { get }

    // MARK: - Inputs
    @Input var signIn: (username: String, password: String) { get } // Property 'signIn' declared inside a protocol cannot have a wrapper
}
```

This is a bit of a show stopper... I don't usually use protocols for view models but for other Combine friendly dependencies I might create 
I want to be able to enforce strict input/outputs.

Take two... let's try using a concrete type:

```swift
struct AnyConsumer<Output> {
    private let subject = PassthroughSubject<Output, Never>()

    func send(_ value: Output) {
        subject.send(value)
    }
}
```

`AnyConsumer` feels like a nice parallel with `AnyPublisher` and now we can use it in our protocol like so:

```swift
protocol AuthViewModelType {
    // MARK: - Outputs
    var signInResult: AnyPublisher<Result<Token, Error>, Never> { get }

    // MARK: - Inputs
    var signIn: AnyConsumer<(username: String, password: String)> { get }
}
```

Let's update our view model again with these changes:

```swift
class AuthViewModel: AuthViewModelType {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Inputs
    let signIn = AnyConsumer<(username: String, password: String)>()

    // MARK: - Lifecycle
    init() {
        signInResult = signIn
            .subject // 'subject' is inaccessible due to 'private' protection level
            .flatMap { input in
                return API
                    .authenticate(input.username, input.password)
                    .materialize()
            }
            .eraseToAnyPublisher()
    }
}
```

Moving to a concrete type allowed us to enforce our strict input in the protocol, but we lost the encapsulation benefits of the PropertyWrapper approach.

What we need is a combination of these two approaches to get all the benefits and, as it turns out, you can do exactly that.

We can use a PropertyWrapper to expose the `Subject` for the enclosing type exclusively but keep it `private` for everything else.

Lets update `AnyConsumer` and see what that looks like:

```swift
struct AnyConsumer<Output> {
    @propertyWrapper
    struct Accessor {
        let wrappedValue: AnyConsumer<Output>

        var subject: PassthroughSubject<Output, Never> { wrappedValue.subject }
    }

    private let subject = PassthroughSubject<Output, Never>()

    public func send(_ value: Output) {
        subject.send(value)
    }
}
```

Using this `@AnyConsumer.Accessor` property from our view model unlocks exclusive access to the underlying `subject`.

This means our view model can once again use the values being sent to perform the work and drive the outputs:

```swift
class AuthViewModel: AuthViewModelType {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Inputs
    @AnyConsumer.Accessor var signIn = AnyConsumer<(username: String, password: String)>()

    // MARK: - Lifecycle
    init() {
        signInResult = _signIn
            .subject
            .flatMap { input in
                return API
                    .authenticate(input.username, input.password)
                    .materialize()
            }
            .eraseToAnyPublisher()
    }
}
```

As before, anything using the view model can _only_ see and call `.send`:

```swift
viewModel.signIn.send((username: "...", password: "..."))
```

It took a bit to get here, but we have managed to obtain our strict input/output separation.

## Wrap up

Congrats for hanging in this far! Using a PropertyWrapper to conditionaly expose access to things is certainly one of the more interesting uses of 
PropertyWrappers I have played with lately but I think the results are pretty neat.

As always, feel free to reach out with any questions or comments!
