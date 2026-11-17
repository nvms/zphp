<?php
// a failed unserialize() frees what it read so far (the handles come back),
// runs the destructors of objects without __wakeup, and refuses a value for
// a virtual property

class T {
    public $a {
        get => 1;
    }
    public $b;
}
class D {
    public $x;
    function __destruct() { echo "destruct D\n"; }
}
class W {
    public $x;
    function __wakeup() { echo "wakeup W\n"; }
    function __destruct() { echo "destruct W\n"; }
}

set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    return true;
});

var_dump(unserialize('O:8:"stdClass":1:{s:1:"a";X}'));
var_dump(new stdClass);
var_dump(unserialize('O:1:"T":1:{s:1:"a";i:1;}'));
var_dump(new stdClass);
var_dump(unserialize('O:1:"T":1:{s:1:"b";X}'));
var_dump(new stdClass);
var_dump(unserialize('O:1:"D":1:{s:1:"x";X}'));
var_dump(unserialize('a:2:{i:0;O:1:"D":0:{}i:1;X}'));
var_dump(unserialize('O:1:"W":1:{s:1:"x";X}'));
var_dump(unserialize('a:2:{i:0;O:1:"W":0:{}i:1;X}'));
var_dump(new stdClass);
var_dump(unserialize('O:1:"T":1:{s:1:"b";i:3;}'));
echo "end\n";
