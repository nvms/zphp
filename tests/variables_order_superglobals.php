<?php
// variables_order decides whether $_ENV and $_SERVER are filled: without E
// or S each is an empty array, argv included
$code = 'echo ini_get("variables_order"), " env=", count($_ENV) > 0 ? "filled" : "empty", " server=", count($_SERVER) > 0 ? "filled" : "empty", " argv=", isset($_SERVER["argv"]) ? "yes" : "no", " argc=", $argc, "\n";';
foreach (['GPC', 'GPCS', 'EGPC', 'EGPCS', 'egpcs'] as $order) {
    echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d variables_order=' . $order . ' -r ' . escapeshellarg($code) . ' 2>&1');
}
