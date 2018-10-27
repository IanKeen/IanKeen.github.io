---
layout: post
title: Omitting Codable properties
commentIssueId: 8
tags: codable
---

`Codable` was a pretty great addition to Swift, among other things it can drastically reduce the amount of code needed when working with a REST API. This magical feature can quickly become frustrating however when you need a model that isn't a 1:1 match with the incoming data.

One example might be that you have some additional data you want to add to your model that can only be created on device. There are a couple of options, you might have server/client representations of the model and convert one to the other. Alternatively you could just make the property optional.

The former may not be an option, if you have a large number of properties that can be painful to maintain for the sake of 1-2 client side differences. This makes the latter seem more desirable but it requires you make the type conform to `Codable` also... or does it?

Turns out you can actually skip certain properties, and you don't actually need to make them `Codable` at all!

---

## Example

Lets say you have a `User` model that you will receive from your server, but you also have some `ClientData` that your app might want to add afterwards, but never get from, or send to, the server. 

All you need to do is define a custom `CodingKey` which omits the properties you want left out of encoding and decoding _and_ give it a default value, like so:


```swift
struct User: Codable {
   private enum CodingKeys: String, CodingKey {
      case id, name, age
   }
   
   let id: String
   var name: String
   var age: Int
   var clientData: ClientData? = nil
}
```

## That's it!

You can now encode an instance of `User` and the `clientData` won't be part of the resulting `Data`. Conversely when you decode incoming data `clientData` will simply use the default value.

Pretty simple right? - it's generally a better idea to model your data as strictly as possible... for example if `clientData` is required then this may not be ideal - but its a handy trick when you need it.

Big thanks to [Christina Moulton](https://twitter.com/christinamltn) for teaching me this trick 🤘
