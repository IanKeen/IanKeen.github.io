---
layout: post
title: The missing Combine input type
commentIssueId: 17
tags: combine, mvvm, propertywrapper
---

Like most people I have been tinkering with SwiftUI and Combine lately. Mostly using the MVVM pattern since that's what I know best. 
One thing I miss from RxSwift that Combine doesn't seem to have is a dedicated _input only_ type. 
In RxSwift there is a protocol called `Observer` with a provided concrete type of `AnyObserver<T>`. 
An `Observer` only exposes ways to send values _in_ but not subscribe to those changes elsewhere.

So why would this be useful? Well I'm a bit of a stickler for encapsulation. 
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

## Inputs… ?

But didn't we already decide Combine doesn't have any input types? It _does_ have ways to model inputs, they just come with some baggage.

The types Combine gives us to send values are called `Subject`s. _But_, they are _both_ input _and_ output (`Publisher`). 
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

A `PassthroughSubject` does exactly what it  says on the label.  It _passes_ values _through_ that it receives via it's `send` function fulfilling its function as an _input_. It then uses those values as the source for its function as a `Publisher`, or _output_.

Now we have defined an input we can use it to attempt to authenticate and, finally, emit the result through our output. Let's take a look at what some code using our view model might look like:

```swift
let viewModel = AuthViewModel()

viewModel
    .signInResult
    .sink { result in
        print(result) // output: success(Token(value: "foobar"))
    }
    .store(in: &cancellables)

viewModel.signIn.send((username: "iankeen", password: "super_secret_password")) // input
```

Not bad, however remember `Subject`s are both input _and_ output. This means we have also left the door open for code like this:

```swift
viewModel
    .signIn
    .sink { result in
        somethingUnexpected(with: result)
    }
    .store(in: &cancellables)
```

Consider the situation where you happen to be tracking down a bug that occurs when your users attempt to authenticate. 
Because we have exposed a `Subject` we have to check all the subscriptions to the `signInResult` output _but also_ any subscriptions to the `signIn` input! 
This makes things harder than they should be…

Let's take a look at a simple approach to get our encapsulation back:

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
enough to potentially over-engineer an alternative… strap yourself in.

## Inputs!… for real this time

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

There's a fair bit going on in this little snippet so let's unpack it quickly…

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

Since we can't enforce `@Input` it means code that only knows about the `AuthViewModelType` wouldn't have visibility to call the `$signIn.send`  function.

This is a bit of a show stopper. I don't usually use protocols for view models but for other Combine friendly dependencies I might create I want to be able to enforce strict input/outputs.

Take two, let's try using a concrete type:

```swift
struct AnyConsumer<Output> {
    private let subject = PassthroughSubject<Output, Never>()

    func send(_ value: Output) {
        subject.send(value)
    }
}
```

I'm calling this `AnyConsumer` because it feels like a nice parallel with `AnyPublisher`.  This type allows us to expose _just_ the `send` function making this type _input only_ just like we want;
however, if we make the subject `private` nothing is going to be able to access it. It feels like we are stuck in a catch 22.

Let's go with it for now and update the rest of our code; first let's make our protocol enforce our strict input:

```swift
protocol AuthViewModelType {
    // MARK: - Outputs
    var signInResult: AnyPublisher<Result<Token, Error>, Never> { get }

    // MARK: - Inputs
    var signIn: AnyConsumer<(username: String, password: String)> { get }
}
```

The next step is to update our view model to conform to these changes:

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

Just as we expected, while we gained the encapsulation benefits of a strict input type the view model isn't able to access the underlying `Subject` to use the values coming in.

We need a way to expose thee `Subject` but _only_ to our view model. As it turns out we can actually use PropertyWrappers again to accomplish that!

We can bring back our `@Input` PropertyWrapper in a new form. This time it will work _with_ `AnyConsumer` to expose the `Subject` to the enclosing type but will be hidden from everything else.

Lets update `AnyConsumer` and see what that looks like:

```swift
@propertyWrapper
struct Input<Output> {
    let wrappedValue: AnyConsumer<Output>

    var subject: PassthroughSubject<Output, Never> { wrappedValue.subject }
}

struct AnyConsumer<Output> {
    fileprivate let subject = PassthroughSubject<Output, Never>()

    func send(_ value: Output) {
        subject.send(value)
    }
}
```

Now we can Combine (pun intended) our `@Input` PropertyWrapper with our `AnyConsumer` to restrict access to each side of the underlying `Subject`. 

We have exclusive access for the view model to read the input:

```swift
class AuthViewModel: AuthViewModelType {
    // MARK: - Outputs
    let signInResult: AnyPublisher<Result<Token, Error>, Never>

    // MARK: - Inputs
    @Input var signIn = AnyConsumer<(username: String, password: String)>()

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

And, as before, anything using the view model can _only_ see and call `.send`:

```swift
viewModel.signIn.send((username: "...", password: "..."))
```

## Wrap up

So after all that we have ended up with something that allows us to nicely encapsulate access to two sides of a `Subject`.  
Is the extra abstraction worth it over our original private subject/function solution? There are a couple of nice advantages our final solution has that I can think of

Less typing: that's always a nice win. Using `AnyConsumer` we  don't have to maintain a private subject as well as an additional function to get into the `send` function.

An explicit type: having this not only draws a nice parallel with other output types like `AnyPublisher` but it gives us an anchor point for things like UI bindings. 
Think about how you might write a button binding today:

```swift
someButton.combine.tap // example tap publisher
    .sink { [unowned self] in 
        self.viewModel.signIn()
    }
```

Using  `AnyConsumer` we could rewrite this subtly: 

```swift
someButton.combine.tap
    .bind(to: viewModel.signIn)
    .store(in: &cancellables)
```

The change is minor but again it's slightly more concise and we can remove the burden of things like managing memory semantics and capture lists from our users.

That's all I have for now, but I'd love to hear any thoughts on this :)
