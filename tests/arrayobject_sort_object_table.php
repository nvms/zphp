<?php
// ArrayObject sorting an object sorts a separated copy of its property
// table (php's zend_array_dup turns the slots' entries into values), which
// becomes the table: listings and iteration take the sorted order, writes
// through the ArrayObject go to the table, and the slots go their own way

#[AllowDynamicProperties]
class C
{
    public $prop1 = 'x';
    public $prop2 = 'z';
    private $prop3 = 'a';
    public $prop4 = 'x';
}

$c = new C();
$c->dyn = 'b';
$ao = new ArrayObject($c);
$ao->asort();
foreach ($ao as $k => $v) {
    echo "$k=$v\n";
}
var_dump($ao->getArrayCopy());
foreach ($c as $k => $v) {
    echo "obj $k=$v\n";
}
$c->later = 'a';
$ao->offsetUnset('prop1');
$c->prop1 = 'back';
var_dump($c, (array) $c, get_object_vars($c), json_encode($c));
$d = clone $c;
var_dump($d);
echo serialize($c), "\n";
$ao->ksort();
var_dump($c);

class D
{
    public $prop1 = 'x';
    public $prop2 = 'z';
}

$e = new D();
$eo = new ArrayObject($e);
$eo->asort();
$eo['prop1'] = 'new';
var_dump($e->prop1, $eo['prop1'], isset($eo['prop2']), count($eo));
$e->prop2 = 'direct';
var_dump($eo['prop2'], $e);

$f = new D();
$fo = new ArrayObject($f);
$fo->ksort();
$fo->offsetUnset('prop1');
$fo['prop1'] = 'again';
var_dump($f, $fo->getArrayCopy());
foreach ($fo as $k => $v) {
    echo "$k=$v\n";
}

$g = new D();
$go = new ArrayObject($g);
var_dump($go->uasort(fn($a, $b) => strcmp($b, $a)), $g);
