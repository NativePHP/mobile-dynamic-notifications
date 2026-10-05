<?php

namespace NativePHP\DynamicNotifications\Facades;

use Illuminate\Support\Facades\Facade;

/**
 * @method static ?string show(string $title, ?string $message = null, string $symbol = 'bell.fill', string $accent = '#60A5FA', ?int $duration = 3600, ?string $id = null, array $data = [])
 * @method static bool dismiss(?string $id = null)
 *
 * @see \NativePHP\DynamicNotifications\DynamicNotifications
 */
class DynamicNotifications extends Facade
{
    protected static function getFacadeAccessor(): string
    {
        return \NativePHP\DynamicNotifications\DynamicNotifications::class;
    }
}
