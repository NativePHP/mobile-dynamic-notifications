<?php

namespace NativePHP\DynamicNotifications;

use Illuminate\Support\ServiceProvider;

class DynamicNotificationsServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(DynamicNotifications::class, fn () => new DynamicNotifications);
    }
}
