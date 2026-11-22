<?php

namespace NativePHP\DynamicNotifications\Events;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;
use Native\Mobile\Events\Contracts\DispatchableFromNative;

class NotificationTapped implements DispatchableFromNative
{
    use Dispatchable, SerializesModels;

    public function __construct(public string $id, public array $data = []) {}
}
