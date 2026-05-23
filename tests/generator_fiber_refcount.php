<?php
// Stage 2 finer generator + fiber lifetime: handles now refcount on every
// Value copy (push, copyValue, set_local overwrite, PhpArray.set, PhpObject.set).
// at refcount 0 they queue for close; unset's widened drain gate fires the
// close so __destruct timing matches PHP. supersedes 7fae3d1's partial fix.
class T
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

echo "== gen unset closes ==\n";
function gen1() { $local = new T('gen1'); yield 1; yield 2; }
$g = gen1();
foreach ($g as $v) if ($v == 1) break;
echo "before unset\n";
unset($g);
echo "after unset\n";

echo "== fiber unset closes ==\n";
$f = new Fiber(function() {
    $local = new T('fiber1');
    Fiber::suspend();
});
$f->start();
echo "before unset\n";
unset($f);
echo "after unset\n";

echo "== recursive yield from still works (refcount survives pop+delegate) ==\n";
function walk(array $arr): Generator {
    foreach ($arr as $item) {
        if (is_array($item)) yield from walk($item);
        else yield $item;
    }
}
$out = [];
foreach (walk([1, [2, [3, 4], 5], 6]) as $v) $out[] = $v;
echo implode(',', $out), "\n";

echo "== generator stored in array survives via array retain ==\n";
function vals() { $local = new T('arrgen'); yield 1; yield 2; }
$arr = [];
$arr[] = vals();
foreach ($arr[0] as $v) echo "$v ";
echo "\n";
echo "before clear arr\n";
$arr = [];
echo "after clear arr\n";
