<?php

spl_autoload_register(function ($class) {
    if ($class == 'A') {
        class A
        {
            function m(): B {}
            function m2(): B {}
        }
        var_dump(new A);
    } elseif ($class == 'B') {
        class B extends A
        {
            function m(): X {}
            function m2(): Y {}
        }
        var_dump(new B);
    } elseif ($class == 'X') {
        class X extends B {}
        var_dump(new X);
    } else {
        class Y extends B {}
        var_dump(new Y);
    }
});

new B;

?>
