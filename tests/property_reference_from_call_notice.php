<?php
// a property assigned by reference from a call returning a value is fetched
// first: "Only variables should be assigned by reference" comes only when
// the fetch gives a property, after what __get raised
set_error_handler(function ($no, $msg) {
    echo "error: $msg\n";
    return true;
});

function value() {
    echo "call\n";
    return ['k' => 'v'];
}
function &reference() {
    static $kept = 1;
    return $kept;
}

class Plain {
    public $p;
}
$o = new Plain;
$o->p =& value();
var_dump($o->p);
$o->p =& reference();
var_dump($o->p);

class Magic {
    private $hidden;
    public function __get($name) {
        echo "get $name\n";
        return $this->$name . "XXX";
    }
}
$m = new Magic;
try {
    $m->interesting =& value();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
