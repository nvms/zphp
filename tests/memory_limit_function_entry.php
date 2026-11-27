<?php
// a recursion that only calls user functions crosses memory_limit with its
// frames: the fatal comes as a function is entered, also from a destructor
// that runs while an object's properties are released
ini_set('memory_limit', '8M');
ini_set('log_errors', '0');
ini_set('display_errors', '1');

register_shutdown_function(function () {
    echo "shutdown: ", error_get_last()['message'], "\n";
});

class Inner {
    public function __destruct() {
        Inner::__destruct();
    }
}
class Outer {
    public $inner;
    public function __destruct() {
        $this->inner = new Inner;
    }
}

$x = new Outer;
unset($x);
echo "not reached\n";
