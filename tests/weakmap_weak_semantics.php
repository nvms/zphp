<?php
// WeakMap now drops entries when the key object becomes unreachable. wmConstruct
// registers each WeakMap in vm.weakmaps, wmOffsetSet calls objRelease on the
// retain PhpArray.append takes (so __keys does not pin), and the destruct
// drain walks vm.weakmaps to prune __data + __keys entries keyed by the
// just-destructed object.
class K
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

echo "== basic weak drop ==\n";
$wm = new WeakMap;
$a = new K('A');
$b = new K('B');
$wm[$a] = 'val_a';
$wm[$b] = 'val_b';
echo "count=", count($wm), "\n";
unset($a);
echo "after unset a, count=", count($wm), "\n";
unset($b);
echo "after unset b, count=", count($wm), "\n";

echo "== iteration sees only live keys ==\n";
$wm2 = new WeakMap;
$x = new K('X');
$y = new K('Y');
$z = new K('Z');
$wm2[$x] = 1;
$wm2[$y] = 2;
$wm2[$z] = 3;
unset($y);
echo "after unset y, iteration:\n";
foreach ($wm2 as $key => $val) {
    echo "  ", $key->id, " => $val\n";
}

echo "== WeakMap survives multiple weak drops ==\n";
$wm3 = new WeakMap;
$kept = new K('KEPT');
$wm3[$kept] = 'kept_val';
$tmp1 = new K('TMP1');
$wm3[$tmp1] = 't1';
$tmp2 = new K('TMP2');
$wm3[$tmp2] = 't2';
unset($tmp1);
unset($tmp2);
echo "count=", count($wm3), "\n";
echo "kept_val=", $wm3[$kept], "\n";
unset($kept);
echo "after unset kept, count=", count($wm3), "\n";
unset($wm3);
unset($wm2);
unset($x);
unset($z);
unset($wm);
echo "end\n";
