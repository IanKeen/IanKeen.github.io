---
layout: post
title: Cross View Animations with matchedGeometryEffect
commentIssueId: 14
tags: swiftui
---

WWDC this year gave us a ton of new things to play with, SwiftUI being front and center. 
A number of new `@propertyWrapper`s were introduced, one I found particularly interesting was `@Namespace`.

This property wrapper can be used in conjunction with an identifier and the view modifier named `matchedGeometryEffect` to coordinate the animation of a part of the screen when updates occur.
This was in [Whats new in SwiftUI](https://developer.apple.com/videos/play/wwdc2020/10041/) around the 19minute mark. 

Unfortunately the example was super brief and only showed moving an element from within the same view body. 

Let's quickly recap with an example, firstly _without_ `@Namespace` and `matchedGeometryEffect`:

```swift
struct MyView: View {
    @State var left = true

    var body: some View {
        VStack {
            Button("Toggle", action: { withAnimation { left.toggle() } })
            HStack {
                if left {
                    Color.red.frame(width: 100, height: 100)
                    Spacer()

                } else {
                    Spacer()
                    Color.blue.frame(width: 100, height: 100)
                }
            }
            .padding()
        }
    }
}
```

The result looks like this:

<img src="/public/images/cross-view-animations-with-matchedgeometryeffect/001.gif" style="zoom:50%;" />

As you can see using `withAnimation` around the state change gives us a nice fade by default.
Now let's see what happens when we add `@Namespace` and `matchedGeometryEffect`:

```swift
struct MyView: View {
    @State var left = true
    @Namespace var namespace // 1) Add namespace

    var body: some View {
        VStack {
            Button("Toggle", action: { withAnimation { left.toggle() } })
            HStack {
                if left {
                    Color.red.frame(width: 100, height: 100)
                        .matchedGeometryEffect(id: "box", in: namespace) // 2) Add `matchedGeometryEffect` inside namespace
                    Spacer()

                } else {
                    Spacer()
                    Color.blue.frame(width: 100, height: 100)
                        .matchedGeometryEffect(id: "box", in: namespace) // 3) Same here, making sure they use the same `id`
                }
            }
            .padding()
        }
    }
}
```

SwiftUI now animates between these 2 _different_ boxes seamlessly as though you were simply moving the _same_ box.

<img src="/public/images/cross-view-animations-with-matchedgeometryeffect/002.gif" style="zoom:50%;" />

## Animating across Views

One thing that was not shown was how to perform animations like this _across_ different views. For example what happens if we refactor our example like this:

```swift
struct MyView: View {
    @State var left = true

    var body: some View {
        VStack {
            Button("Toggle", action: { withAnimation { left.toggle() } })
            if left { LeftView() }
            else { RightView() }
        }
    }
}

struct LeftView: View {
    var body: some View {
        HStack {
            Color.red.frame(width: 100, height: 100)
            Spacer()
        }
        .padding()
    }
}
struct RightView: View {
    var body: some View {
        HStack {
            Spacer()
            Color.blue.frame(width: 100, height: 100)
        }
        .padding()
    }
}
```

Turns out integrating `@Namespace` and `matchedGeometryEffect` it's not immediately obvious, my first instinct was to just pass the `@Namespace` along like so:

```swift
struct MyView: View {
    @State var left = true
    @Namespace var namespace

    var body: some View {
        VStack {
            Button("Toggle", action: { withAnimation { left.toggle() } })
            if left { LeftView(namespace: _namespace) }
            else { RightView(namespace: _namespace) }
        }
    }
}

struct LeftView: View {
    @Namespace var namespace

    var body: some View {
        HStack {
            Color.red.frame(width: 100, height: 100)
                .matchedGeometryEffect(id: "box", in: namespace)
            Spacer()
        }
        .padding()
    }
}
struct RightView: View {
    @Namespace var namespace

    var body: some View {
        HStack {
            Spacer()
            Color.blue.frame(width: 100, height: 100)
                .matchedGeometryEffect(id: "box", in: namespace)
        }
        .padding()
    }
}
```

However this just resulted in the default fade animation...

<img src="/public/images/cross-view-animations-with-matchedgeometryeffect/001.gif" style="zoom:50%;" />

The reason is `@Namespace` only has a single `init()` and it's `wrappedValue` is read-only. 
So by using the `@Namespace` property wrapper we are actually creating different instances in the left/right views rather than using the one we pass in.

However for this to work we still need to pass in the namespace since `matchedGeometryEffect` needs one. If we look at the namespace parameter of `matchedGeometryEffect` it actually wants a `Namespace.ID` which happens to be the `wrappedValue` from `@Namespace`. This means we should be able to just pass the `Namespace.ID` instead, let's try:

```swift
struct MyView: View {
    @State var left = true
    @Namespace var namespace

    var body: some View {
        VStack {
            Button("Toggle", action: { withAnimation { left.toggle() } })
            if left { LeftView(namespace: namespace) }
            else { RightView(namespace: namespace) }
        }
    }
}

struct LeftView: View {
    var namespace: Namespace.ID

    var body: some View {
        HStack {
            Color.red.frame(width: 100, height: 100)
                .matchedGeometryEffect(id: "box", in: namespace)
            Spacer()
        }
        .padding()
    }
}
struct RightView: View {
    var namespace: Namespace.ID

    var body: some View {
        HStack {
            Spacer()
            Color.blue.frame(width: 100, height: 100)
                .matchedGeometryEffect(id: "box", in: namespace)
        }
        .padding()
    }
}
```

<img src="/public/images/cross-view-animations-with-matchedgeometryeffect/002.gif" style="zoom:50%;" />

Success!

## Recap

Using these features you can create some fantastic interactions with _very little code_. The same interactions with `UIKit` would involve _numerous_ additional types and fairly complex code to create the same transitions.  

Remember that to 'link' elements with  `matchedGeometryEffect` you need to:

- Ensure they are in the same `Namespace` by using the same instance.
- Ensure they have the same `id`.

And SwiftUI will take care of the rest!
