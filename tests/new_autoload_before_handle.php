<?php
// `new C` looks the class up (autoloading it) before it takes the object's
// handle, so objects the autoloader makes get the lower handles; an
// autoloader that throws stops the `new` before its arguments run

spl_autoload_register(function ($class) {
    if ($class === 'Thrower') throw new Exception("refusing $class");
    eval("class $class { public function __construct(...\$args) {} }");
    var_dump(new stdClass);
});

function arg($v) { echo "argument $v\n"; return $v; }

var_dump(new Loaded(arg(1)));
var_dump(new Loaded(arg(2)));
try {
    new Thrower(arg(3));
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
var_dump(new Another);
