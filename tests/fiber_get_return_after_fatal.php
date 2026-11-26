<?php
// a fiber that ended with a fatal error has no return value: getReturn()
// says so (ZEND_FIBER_FLAG_BAILOUT)
$threw = new Fiber(function () { throw new Exception("x"); });
try { $threw->start(); } catch (Exception $e) {}
try { $threw->getReturn(); } catch (FiberError $e) { echo $e->getMessage(), "\n"; }

register_shutdown_function(static function (): void {
    global $fiber;
    try {
        var_dump($fiber->isTerminated());
        var_dump($fiber->getReturn());
    } catch (FiberError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
});

$fiber = new Fiber(static function (): void {
    var_dump(new class { public function __debugInfo() { return ''; } });
});
$fiber->start();
