<?php

namespace NativePHP\DynamicNotifications\Events;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class NotificationTapped
{
    use Dispatchable, SerializesModels;

    public function __construct(public string $id, public array $data = []) {}
}
