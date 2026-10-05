<?php

use NativePHP\DynamicNotifications\DynamicNotifications;

require __DIR__.'/../src/DynamicNotifications.php';

$notifications = new DynamicNotifications;
if ($notifications->show('Preview') !== null || $notifications->dismiss() !== false) {
    throw new RuntimeException('Off-device calls should be inert.');
}
echo "PASS: off-device behavior\n";
