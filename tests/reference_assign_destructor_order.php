<?php
// a reference assignment to a property frees what the property held before
// the result is read, so a destructor that writes through the new reference
// shows in the result (php's GH-10168)
class Holder {
    public static $s;
    public $p;
    public $q;
}
class ClearsStatic {
    function __destruct() {
        echo "destruct clears static\n";
        Holder::$s = null;
    }
}
class ClearsProp {
    function __destruct() {
        global $h;
        echo "destruct clears prop\n";
        $h->q = null;
    }
}
Holder::$s = new ClearsStatic;
$h = new Holder;
$h->p = 5;
var_dump(Holder::$s = &$h->p);
var_dump($h->p);

$h->q = new ClearsProp;
$other = new Holder;
$other->p = 'kept';
var_dump($h->q = &$other->p);
var_dump($other->p);
var_dump(Holder::$s = &$other->p);
