<?php
// method_exists() on a class named by string loads it first, so the class's
// own methods count on the call that autoloads it
spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    if ($class === 'Thrower') throw new RuntimeException("cannot load $class");
    if ($class === 'Base') { eval('class Base { function inherited() {} }'); return; }
    if ($class === 'Ns\Invokable') { eval('namespace Ns; class Invokable extends \Base { function __invoke() {} private function hidden() {} }'); return; }
});
var_dump(method_exists('Ns\Invokable', '__invoke'));
var_dump(method_exists('Ns\Invokable', 'INHERITED'));
var_dump(method_exists('Ns\Invokable', 'hidden'));
var_dump(method_exists('Ns\Invokable', 'missing'));
var_dump(method_exists('NoSuchClass', 'x'));
try {
    method_exists('Thrower', 'x');
} catch (RuntimeException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
