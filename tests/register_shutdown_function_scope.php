<?php
// register_shutdown_function resolves its callback where it is registered:
// self:: names the class, an inferred $this is kept, and an invalid
// callback is a TypeError then
set_error_handler(function ($no, $msg) { echo "deprecated: ", $msg, "\n"; return true; });
class Test {
    public $name = 'test';
    function register() {
        register_shutdown_function('Test::method');
        register_shutdown_function([$this, 'withArgs'], 1, 2);
    }
    function method() { echo "method with ", get_class($this), " ", $this->name, "\n"; }
    function withArgs($a, $b) { echo "args $a $b\n"; }
    static function main() {
        register_shutdown_function(['self', 'onShutdown']);
        register_shutdown_function('static::onShutdown');
    }
    static function onShutdown() { echo "static ", static::class, "\n"; }
}
(new Test)->register();
Test::main();
register_shutdown_function(function () { echo "closure\n"; });
register_shutdown_function('printf', "printf %s\n", 'arg');
try {
    register_shutdown_function('no_such_function');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    register_shutdown_function(['Test', 'nope']);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
echo "end of script\n";
