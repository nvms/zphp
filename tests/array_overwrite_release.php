<?php
// Stage 2 element-overwrite release in the array_set / array_set_local
// opcode paths: when `$arr[key] = newValue` replaces an existing entry, the
// array's retain on the OLD value is dropped so the displaced object can
// reach refcount 0 and __destruct fires promptly. previously the displaced
// value leaked until end-of-request because PhpArray.set (no VM access)
// could not release. roadmap item 1 sub-bullet.
class T
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

function makeArr() { $a = []; return $a; }

echo "== string-key overwrite ==\n";
$arr = makeArr();
$arr['k'] = new T('A');
echo "before overwrite\n";
$arr['k'] = new T('B');
echo "after overwrite\n";
$arr['k'] = 42;
echo "after scalar overwrite (B destructs)\n";

echo "== int-key chain ==\n";
$arr2 = makeArr();
$arr2[5] = new T('C');
echo "before C->D\n";
$arr2[5] = new T('D');
echo "before D->E\n";
$arr2[5] = new T('E');
echo "before E->scalar\n";
$arr2[5] = 0;
echo "done\n";
