---
layout: post
title: Your ViewController isn’t a View
commentIssueId: 2
tags: mvc viewcontroller
---

Today I’m going to step through a very under utilized way to slim down your `UIViewController`s.

- - - -

## Example
Lets look at a simple login screen:
![](/images/your-viewcontroller-isnt-a-view/example.gif)

## Breaking down View and ViewController
Lets take a high level look at this screens functionality:

* Contains UI elements
* Lays out UI elements
* Performs Facebook login
* Performs Google login
* Toggles the loading indicator
* Toggles the email login input
* Toggles the keyboard
* Resizing based on the keyboard
* Performs email login

This is pretty standard list for a screen like this and its common to see _all_ of this contained in the view controller. Over time having a controller handling all these responsibilities can make it harder to understand as well as harder to _change_.

### Blurred lines
Our first step to separating our code is to figure out what belongs where. What we want to do is group the items in our list in terms of how the screen _looks_ vs what the screen _does_. This defines our `UIView` and `UIViewController` respectively. 

This can be harder than it sounds…

As we move through each item you may notice some don’t _really_ fit completely in a single category.  Lets look at a few:

* Toggling the loading indicator: This is made up of how that should _look_ but it can show or hide based on what the screen _does_.

* Toggling the email login elements: This is a state transition so you might think to put that in the controller - however because it is a _view state_ transition that doesn’t rely on any outside logic it should really live in the view in this instance. Remember, theres no reason a view can’t react to things like button taps!

* Dealing with the keyboard can be especially tricky since it exists _outside_ the immediate view hierarchy. Just use your best judgement when it comes to elements like this.

Now that we’ve had a think about these things lets break our original items out further to create our new lists. 

### How it looks (UIView)
* Contains UI elements
* Appearance for social logins
* Appearance for email login
* Toggle appearance based on social/email state
* Animate the loading indicator in/out
* Show/hide keyboard

### What it does (UIViewController)
* Performs Facebook login
* Performs Google login
* Performs email login
* Show/hide loading indicator
* Resize when keyboard shows/hides

We can see that what this screen _really_ does is much more than we originally thought. However now that we have a clearer separation of concerns we can break the original view controller down into a separate view and controller that handle their own, distinct, roles.

So once we have moved the view code into a custom `UIView` how do we bring that into a `UIViewController`?

- - - -

## Code UI
You have no doubt used a number of overrides in `UIViewController` . `viewDidLoad`, `viewDidAppear` etc.. however there is a lesser known override called `loadView`.

### Custom Views
`loadView` allows you to insert a custom `UIView` that the `UIViewController` will use as its `view` simply by assigning it, for example:

```swift
override func loadView() {
    self.view = MyCustomView()
}
```

### Accessing the custom view
How that our custom view is loaded we want typed access to it. The most straight forward way to do this is with a computed property:

```swift
var customView: MyCustomView { return view as! MyCustomView }
```

Now in your `UIViewController` you access the typed version of the view via the new  `customView` property instead of `self.view`  (the `!` is safe here as we can guarantee `view` will always be `MyCustomView`)

### Bonus
Here is a nice generic `UIViewController` subclass I like to use to simplify this pattern.

```swift
class ViewController<T: UIView>: UIViewController {
    // MARK: - View Separation
    var customView: T { return view as! T }

    // MARK: - Lifecycle
    override func loadView() {
        self.view = T()
    }
}
```

With this you can define your view controllers as:
```swift
class MyViewController: ViewController<MyView> {
   //you now get a `customView` property typed as `MyView` for free
}
```

## Storyboard / Nib UI
The process for storyboards and nibs are the same.

### Custom Views
Open the storyboard or nib, find your view controllers view in Interface Builders document outline.
![](/images/your-viewcontroller-isnt-a-view/outline.png)

In the identity inspector update the view class to the type of your custom view.
![](/images/your-viewcontroller-isnt-a-view/inspector.png)

### Accessing the custom view
As with the code based method, we will want typed access to our custom view. We use a computed property again however this time it will be an `IBOutlet`:

```swift
@IBOutlet private var customView: MyCustomView!
```

Finally we just need to hook the `IBOutlet` from the `UIViewController` to the custom `UIView`.
![](/images/your-viewcontroller-isnt-a-view/outlet.png)

- - - -

## Results
So what have we achieved? 

We have defined a clearer separation of concerns between a view and a controller.  Now our view can focus solely on how a screen _looks_ and the controller can focus on what a screen _does_.

This is a technique you can use regardless of whether you build your UIs with code, nibs or storyboards _and_ it will work with any architecture or pattern.

Speaking of patterns… this one is called MVC 😄

You can download a project with an example of all three UI methods ![here](/projects/your-view-controller-isnt-a-view.zip) 
