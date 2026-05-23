<?php
// Stage 2 literal-array orphan fix: `$var = [...]` in function scope now
// emits set_local_transfer (skips copyValue's deep clone) so the literal
// array isn't orphaned with element retains intact. unset's widened drain
// gate also drains pending_array_release so __destruct timing matches PHP.
// only the AST `array_literal` rhs shape qualifies - native returns like
// ArrayObject::getArrayCopy still clone in copyValue because their shallow
// shape would lose isolation without it.
class T
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

echo "== literal in function scope ==\n";
function go() {
    $arr = [new T('A')];
    echo "alive\n";
    unset($arr);
    echo "after unset\n";
}
go();
echo "after go\n";

echo "== two literals in sequence ==\n";
function two() {
    $a = [new T('B')];
    $b = [new T('C')];
    echo "both alive\n";
    unset($a);
    echo "after unset a\n";
    unset($b);
    echo "after unset b\n";
}
two();

echo "== literal with multiple elements ==\n";
function multi() {
    $arr = [new T('D'), new T('E')];
    unset($arr);
    echo "after unset\n";
}
multi();
