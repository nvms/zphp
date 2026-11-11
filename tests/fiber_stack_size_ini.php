<?php
// fiber.stack_size: a negative size is refused with a warning, and a fiber
// started with less than a page and its guard page throws

var_dump(ini_get("fiber.stack_size"));
var_dump(ini_set("fiber.stack_size", "-1"));
var_dump(ini_get("fiber.stack_size"));
var_dump(ini_set("fiber.stack_size", "1M"));
$fiber = new Fiber(function () {
    echo "started\n";
});
$fiber->start();
ini_set("fiber.stack_size", "1024");
$fiber = new Fiber(function () {
    echo "not started\n";
});
try {
    $fiber->start();
} catch (Exception $e) {
    echo preg_replace('/\d+/', 'N', $e->getMessage()), "\n";
}
