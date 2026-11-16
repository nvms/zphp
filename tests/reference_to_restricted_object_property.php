<?php
// `$ref =& $o->p` on a readonly or private(set) property holding an object,
// where the scope can't modify it, binds to a copy: replacing $ref leaves
// the property alone, and changing the object through it shows
class Test {
    public readonly object $ro;
    public private(set) object $ps;

    public function __construct() {
        $this->ro = new stdClass;
        $this->ps = new stdClass;
    }

    public function replaceRo() {
        $ref =& $this->ro;
        $ref->touched = true;
        $ref = new ArrayObject;
    }
}

$t = new Test;
$t->replaceRo();
$t->replaceRo();
var_dump($t->ro);

$ref =& $t->ps;
$ref->outside = 1;
$ref = 5;
var_dump($t->ps, $ref);

$name = 'ro';
$ref2 =& $t->$name;
$ref2 = null;
var_dump($t->ro);
