<?php
interface I {}
spl_autoload_register(function() {
    class X {
        function test(): I {}
    }
    class Y extends X {
        function test(): C {}
    }
});
class C extends Z implements C {}
?>
