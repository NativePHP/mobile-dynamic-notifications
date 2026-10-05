<?php

// Dependency-free bridge contract checks. Run: php tests/bridge.php
require __DIR__.'/../src/DynamicNotifications.php';

use NativePHP\DynamicNotifications\DynamicNotifications;

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
echo "PASS: bridge payloads, IDs, duration, validation, dismissals, and error handling\n";
