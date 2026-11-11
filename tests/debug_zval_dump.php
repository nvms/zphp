<?php
// debug_zval_dump: var_dump's layout with reference counts, "interned"
// strings and empty arrays, "packed" lists and references; the counts here
// are ones zphp's model agrees with php on
$n = 3;
$a = range(1, $n);
debug_zval_dump($a);
$b = $a;
debug_zval_dump($a);
$o = new stdClass;
$o->x = 1;
debug_zval_dump($o);
$o2 = $o;
debug_zval_dump($o);
$s = str_repeat("ab", $n);
debug_zval_dump($s);
$t = $s;
debug_zval_dump($s);
debug_zval_dump(1, 1.5, -0.0, true, null, "", "x", []);
$f = fopen(__FILE__, 'r');
debug_zval_dump($f);
$nested = ['x' => $o, 'y' => [$s]];
debug_zval_dump($nested);

$r = 1;
$refs = [&$r];
debug_zval_dump($refs);
$refs[] = &$r;
debug_zval_dump($refs);
unset($refs[1]);
debug_zval_dump($refs);

#[AllowDynamicProperties]
class P {
    public $pub = 1;
    protected $prot = 2.5;
    private $priv = "x";
    public int $typed;
}
$p = new P;
debug_zval_dump($p);
$p->self = $p;
debug_zval_dump($p);
