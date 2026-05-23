<?php
// compound assignment through a ref-bound variable - `$r .= 'x'`, `$r += 1`,
// etc. - must propagate the new value back to the underlying storage the ref
// points at (obj prop, static prop, dynamic prop, array elem). concat_assign
// previously updated only the cell and didn't call propagateCellWrite, so
// the obj/static/array storage diverged from $r. arithmetic compound ops
// (+=, -=, *=, /=) already worked because they compile to get + binop +
// set_local, and set_local correctly routes ref-bound writes.
class C
{
    public $n = 5;
    public $z = 'init';
    public static $s = 10;
}

echo "== .= on obj prop ref ==\n";
$o = new C;
$r = &$o->z;
$r .= '_X';
$r .= '_Y';
echo "z=", $o->z, "\n";

echo "== .= on static prop ref ==\n";
class D { public static $s = 'hello'; }
$rs = &D::$s;
$rs .= ' world';
echo "D::s=", D::$s, "\n";

echo "== .= on dynamic prop ref ==\n";
$o2 = new C;
$name = 'z';
$rd = &$o2->$name;
$rd .= ' suffix';
echo "z=", $o2->z, "\n";

echo "== .= on array elem ref ==\n";
$arr = ['k' => 'base'];
$re = &$arr['k'];
$re .= '_appended';
echo "arr[k]=", $arr['k'], "\n";

echo "== += / -= / *= still work ==\n";
$o3 = new C;
$ra = &$o3->n;
$ra += 3;
$ra -= 1;
$ra *= 2;
echo "n=", $o3->n, "\n";
