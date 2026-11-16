<?php
// a call that returned a reference passes that reference to a by-reference
// parameter; a call that returned a value passes a temporary, with a notice,
// even right after a call that returned a reference. `$b =& $a` passes the
// reference it made
class C {
    public $p = "prop";
    static function sval() { global $a; return $a; }
    static function &sref() { global $a; return $a; }
    function val() { global $a; return $a; }
    function &ref() { global $a; return $a; }
    function &prop() { return $this->p; }
}
function val() { global $a; return $a; }
function &ref() { global $a; return $a; }
function foo(&$r) { var_dump($r); $r = "changed"; }

set_error_handler(function ($no, $msg, $file, $line) { echo "notice: $msg (line $line)\n"; return true; });

$c = new C;
foreach (['val', 'ref'] as $kind) {
    $a = "original";
    foo($kind());
    var_dump($a);
    $a = "original";
    foo($kind === 'val' ? C::sval() : C::sref());
    var_dump($a);
    $a = "original";
    foo($c->$kind());
    var_dump($a);
}

$a = "original";
foo(ref());
$a = "original";
foo($c->val());
var_dump($a);

foo($c->prop());
var_dump($c->p);

$a = "a";
foo($b =& $a);
var_dump($a, $b);

function bar(&$x, &$y) { $x .= "1"; $y .= "2"; }
$s = "s";
bar($t =& $s, $s);
var_dump($s, $t);
