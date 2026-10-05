# Dynamic Notifications

Dynamic Island-style **in-app** notifications for NativePHP Mobile on iOS 18.2+.
Native SwiftUI draws and animates the fluid pill; no JavaScript animation engine,
notification permission, background service, or third-party native SDK is required.

Inspired by [expo-dynamic-notifications](https://github.com/rit3zh/expo-dynamic-notifications).
This is an independent native implementation, not a React Native wrapper.

## Demo

<a href="https://www.youtube.com/watch?v=UzB9ygfaPSI">
  <img src="https://img.youtube.com/vi/UzB9ygfaPSI/hqdefault.jpg" alt="Watch the Dynamic Notifications demo on YouTube" width="392" />
</a>

[Watch the demo on YouTube](https://www.youtube.com/watch?v=UzB9ygfaPSI).

## Install in your app

Run Composer in the **consuming application**, never inside this plugin:

```sh
composer config repositories.dynamic-notifications vcs https://github.com/NativePHP/mobile-dynamic-notifications
composer require nativephp/mobile-dynamic-notifications:dev-main
php artisan native:plugin:register nativephp/mobile-dynamic-notifications
```

Requires NativePHP Mobile 4.5.0+ and iOS 18.2+. Rebuild your iOS app to compile
the Swift code. The initial implementation is iOS-only; no Android renderer ships
in this package yet. No Packagist listing or tagged release is required for the
VCS installation above.

For local development, use a Composer `path` repository pointing to your clone
instead of the `vcs` repository.

## Show and dismiss

```php
use NativePHP\DynamicNotifications\Facades\DynamicNotifications;

$id = DynamicNotifications::show(
    title: 'All changes saved',
    message: 'Your workspace is up to date.',
    symbol: 'checkmark', // SF Symbol
    accent: '#82D9AE',
    duration: 3600, // milliseconds; null stays until dismissed
    data: ['document' => 42],
);

DynamicNotifications::dismiss($id);
```

An omitted ID is generated. Showing another notification replaces the current one.
A targeted dismissal only closes the matching ID. On a desktop without the native
bridge, `show()` returns null and `dismiss()` returns false. Native errors throw.

## Events

In an active native component:

```php
use Native\Mobile\Attributes\On;
use NativePHP\DynamicNotifications\Events\NotificationTapped;
use NativePHP\DynamicNotifications\Events\NotificationDismissed;

#[On(NotificationTapped::class)]
public function tapped(string $id, array $data = []): void
{
    // Open the relevant screen or perform an application action.
}

#[On(NotificationDismissed::class)]
public function dismissed(string $id, string $reason, array $data = []): void
{
    // reason: tap, swipe, timeout, programmatic, replaced, background, layoutChanged
}
```

Tap fires once, then dismissal fires after the exit animation. These are ordinary
NativePHP component events; do not assume an EDGE event also invokes global Laravel
listeners. Dismissal on replacement/background/layout change is immediate.

## Behavior and limits

- Portrait iPhones with an island-sized safe area use an approximate island origin.
  iOS provides no public hardware-island bounds API. Other layouts use a top banner.
- This does not create Live Activities or put content inside Apple's system island.
- Touches outside the card pass through; the overlay never becomes the key window.
- Supports Reduce Motion, Dynamic Type, VoiceOver announcements and dismissal.
- Dismisses when the owning scene enters the background or changes orientation.
- Title, two-line message, SF Symbol, tint and duration are supported. Remote avatars
  and arbitrary custom content are not implemented in this first version.

## Push notifications

This plugin presents notifications; it does not receive APNs or FCM messages.
Applications can call `show()` after receiving foreground data from their own
push or websocket integration. There is no automatic Firebase adapter yet.
The overlay requires a foreground app and cannot appear on the lock screen or
while the application is in the background.

## Checks

```sh
php tests/bridge.php
php tests/off-device.php
```

`examples/SimulatorDemo.swift` is an optional standalone native harness. Compile it
alongside `resources/ios/DynamicNotificationFunctions.swift` in an iOS simulator app.
It substitutes the PHP bridge, so use a consuming NativePHP app to verify end-to-end
event delivery.
