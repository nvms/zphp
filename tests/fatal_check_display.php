<?php
// a fatal error from a declaration check is reported like any other fatal:
// shown per display_errors, logged per log_errors
ini_set('display_errors', '1');
ini_set('log_errors', '0');
echo "before\n";
if (true) {
    class A { public final $prop; }
    class B extends A { public $prop { get => 1; } }
}
echo "not reached\n";
