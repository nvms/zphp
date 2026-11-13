<?php
// an undefined static method is reported with the class's declared spelling

class MixedCase {
    public static function __callStatic_unused() {}
}

foreach (['mixedcase::missing', 'MIXEDCASE::other'] as $call) {
    try {
        [$class, $method] = explode('::', $call);
        $class::$method();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    mixedcase::missing();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    MIXEDCASE::gone(1, 2);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
