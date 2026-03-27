<?php
spl_autoload_register(function ($class) {
    $map = [
        'Psr\\Http\\Message\\' => ['vendor/psr/http-message/src/', 'vendor/psr/http-factory/src/'],
        'Psr\\Log\\' => ['vendor/psr/log/src'],
        'Psr\\Container\\' => ['vendor/psr/container/src/'],
        'Fig\\Http\\Message\\' => ['vendor/fig/http-message-util/src/'],
        'Slim\\' => ['vendor/slim/slim/Slim'],
        'FastRoute\\' => ['vendor/nikic/fast-route/src/'],
        'Slim\\Psr7\\' => ['vendor/slim/psr7/src'],
        'Psr\\Http\\Server\\' => ['vendor/psr/http-server-middleware/src/', 'vendor/psr/http-server-handler/src/'],
    ];
    foreach ($map as $prefix => $dirs) {
        $len = strlen($prefix);
        if (strncmp($prefix, $class, $len) === 0) {
            $relative = substr($class, $len);
            foreach ($dirs as $dir) {
                $file = $dir . '/' . str_replace('\\', '/', $relative) . '.php';
                if (file_exists($file)) {
                    require $file;
                    return;
                }
            }
        }
    }
});
require_once 'vendor/ralouphie/getallheaders/src/getallheaders.php';
require_once 'vendor/nikic/fast-route/src/functions.php';
