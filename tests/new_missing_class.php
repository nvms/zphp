<?php
// `new` of a class no autoloader declares fails before its arguments run,
// asking each autoloader once

spl_autoload_register(function ($class) {
    echo "autoload $class\n";
});

function arg() {
    echo "argument evaluated\n";
    return 1;
}

try {
    new Missing(arg());
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    new \Other\Missing(arg());
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
