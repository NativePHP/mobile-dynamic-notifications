<?php

namespace NativePHP\DynamicNotifications;

use InvalidArgumentException;
use RuntimeException;

class DynamicNotifications
{
    /** Show a foreground banner. Returns its ID, or null when no native bridge is available. */
    public function show(
        string $title,
        ?string $message = null,
        string $symbol = 'bell.fill',
        string $accent = '#60A5FA',
        ?int $duration = 3600,
        ?string $id = null,
        array $data = [],
    ): ?string {
        if (trim($title) === '') {
            throw new InvalidArgumentException('A notification title is required.');
        }

        if ($duration !== null && ($duration < 250 || $duration > 86400000)) {
            throw new InvalidArgumentException('Duration must be null or between 250 and 86400000 milliseconds.');
        }

        if (! preg_match('/^#[0-9a-fA-F]{6}$/', $accent)) {
            throw new InvalidArgumentException('Accent must be a six-digit hex color, such as #60A5FA.');
        }

        $id ??= bin2hex(random_bytes(16));

        if (trim($id) === '') {
            throw new InvalidArgumentException('Notification ID must not be empty.');
        }

        $result = $this->call('Show', compact('id', 'title', 'message', 'symbol', 'accent', 'duration', 'data'));

        return ($result['success'] ?? false) ? $id : null;
    }

    /** An ID prevents a stale caller from dismissing a newer notification. */
    public function dismiss(?string $id = null): bool
    {
        return (bool) ($this->call('Dismiss', ['id' => $id])['dismissed'] ?? false);
    }

    private function call(string $method, array $parameters): array
    {
        // Encode before entering native code; invalid user data must never become an empty payload.
        $json = json_encode($parameters, JSON_THROW_ON_ERROR);

        if (! function_exists('nativephp_call')) {
            return [];
        }

        $response = nativephp_call('DynamicNotifications.'.$method, $json);

        if (! $response) {
            throw new RuntimeException('No response from the DynamicNotifications bridge.');
        }

        $result = json_decode($response, true, flags: JSON_THROW_ON_ERROR);

        if (! is_array($result)) {
            throw new RuntimeException('Invalid DynamicNotifications bridge response.');
        }

        if (isset($result['error'])) {
            throw new RuntimeException(is_string($result['error']) ? $result['error'] : json_encode($result['error'], JSON_THROW_ON_ERROR));
        }

        return $result;
    }
}
