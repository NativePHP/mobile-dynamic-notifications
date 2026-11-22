<?php

// Bridge contract checks. Run: php tests/bridge.php
// Only the event checks at the end need `composer install`; everything else is dependency-free.
require __DIR__.'/../src/DynamicNotifications.php';

use Native\Mobile\Events\Contracts\DispatchableFromNative;
use NativePHP\DynamicNotifications\DynamicNotifications;
use NativePHP\DynamicNotifications\Events\NotificationDismissed;
use NativePHP\DynamicNotifications\Events\NotificationTapped;

$calls = [];
$response = '{"success":true}';
function nativephp_call(string $method, string $json): string
{
    global $calls, $response;
    $calls[] = [$method, json_decode($json, true, flags: JSON_THROW_ON_ERROR)];

    return $response;
}
function check(bool $condition, string $message): void
{
    if (! $condition) {
        throw new RuntimeException($message);
    }
}
function fails(callable $callback, string $exception): void
{
    try {
        $callback();
    } catch (Throwable $error) {
        check($error instanceof $exception, 'Unexpected exception: '.$error::class);

        return;
    }
    throw new RuntimeException('Expected '.$exception);
}

$notifications = new DynamicNotifications;
$id = $notifications->show('Saved', message: 'All changes synced', duration: null, data: ['route' => '/inbox']);
check(is_string($id) && strlen($id) === 32, 'Generated ID missing');
check($calls[0][0] === 'DynamicNotifications.Show', 'Wrong bridge method');
check($calls[0][1]['duration'] === null, 'Persistent duration lost');
check($calls[0][1]['data'] === ['route' => '/inbox'], 'Event data lost');
check($notifications->show('Updated', id: 'upload-1') === 'upload-1', 'Explicit ID lost');
check($calls[1][1]['duration'] === 3600, 'Default duration incorrect');
$count = count($calls);
fails(fn () => $notifications->show('  '), InvalidArgumentException::class);
fails(fn () => $notifications->show('Title', duration: 0), InvalidArgumentException::class);
fails(fn () => $notifications->show('Title', duration: -1), InvalidArgumentException::class);
fails(fn () => $notifications->show('Title', duration: 86400001), InvalidArgumentException::class);
fails(fn () => $notifications->show('Title', accent: 'red'), InvalidArgumentException::class);
fails(fn () => $notifications->show('Title', id: ''), InvalidArgumentException::class);
fails(fn () => $notifications->show('Title', data: [NAN]), JsonException::class);
check(count($calls) === $count, 'Invalid arguments reached native code');
$response = '{"dismissed":true}';
check($notifications->dismiss('upload-1'), 'Dismiss result lost');
check(end($calls) === ['DynamicNotifications.Dismiss', ['id' => 'upload-1']], 'Targeted dismiss ID lost');
$response = '{"dismissed":false}';
check(! $notifications->dismiss(), 'No-op dismissal reported as success');
$response = '{"error":"No foreground window"}';
fails(fn () => $notifications->show('Title'), RuntimeException::class);
$response = '';
fails(fn () => $notifications->show('Title'), RuntimeException::class);
$response = 'null';
fails(fn () => $notifications->show('Title'), RuntimeException::class);
$response = '{';
fails(fn () => $notifications->show('Title'), JsonException::class);

// DynamicNotificationFunctions.swift sends both events through /_native/api/events, which
// nativephp/mobile 4.6.1+ refuses unless the class implements DispatchableFromNative.
// Laravel's event traits come from the host app, so stand-ins are enough to load the classes.
require __DIR__.'/../vendor/autoload.php';
trait LaravelEventTraitStandIn {}
foreach (['Illuminate\\Foundation\\Events\\Dispatchable', 'Illuminate\\Queue\\SerializesModels'] as $trait) {
    if (! trait_exists($trait)) {
        class_alias(LaravelEventTraitStandIn::class, $trait);
    }
}
foreach ([NotificationTapped::class, NotificationDismissed::class] as $event) {
    check(class_exists($event), $event.' is missing');
    check(is_subclass_of($event, DispatchableFromNative::class), $event.' must implement DispatchableFromNative');
}
echo "PASS: bridge payloads, IDs, duration, validation, dismissals, error handling, and native events\n";
