<?php
// an undeclared static property names its class as declared, however the
// class was spelled
class MixedCase { public static $x = 1; }
foreach (['MixedCase', 'mixedcase', 'MIXEDCASE', 'closure', 'stdclass'] as $class) {
    try {
        var_dump($class::$missing);
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(mixedcase::$x);
