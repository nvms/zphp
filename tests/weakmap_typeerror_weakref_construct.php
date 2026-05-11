<?php
$wm = new WeakMap;
$o = new stdClass;
$wm[$o] = 1;

echo $wm instanceof Countable ? "y" : "n", "\n";
echo $wm instanceof ArrayAccess ? "y" : "n", "\n";
echo $wm instanceof IteratorAggregate ? "y" : "n", "\n";

$wr = WeakReference::create($o);
echo $wr instanceof WeakReference ? "y" : "n", "\n";

try { $wm["string-key"] = "v"; } catch (Throwable $e) { echo get_class($e), "\n"; }
try { $wm[42] = "v"; } catch (Throwable $e) { echo get_class($e), "\n"; }
try { new WeakReference; } catch (Throwable $e) { echo get_class($e), "\n"; }

$wm2 = new WeakMap;
echo count($wm2), "\n";

$a = new stdClass;
$b = new stdClass;
$wm3 = new WeakMap;
$wm3[$a] = "v1";
$wm3[$b] = "v2";

$gotKeys = 0;
foreach ($wm3 as $k => $v) if (is_object($k)) $gotKeys++;
echo $gotKeys, "\n";

$wm4 = new WeakMap;
$arr = [];
for ($i = 0; $i < 3; $i++) {
    $o = new stdClass;
    $o->idx = $i;
    $arr[] = $o;
    $wm4[$o] = $i * 10;
}
foreach ($wm4 as $k => $v) echo $k->idx, "/", $v, " ";
echo "\n";

$wm5 = new WeakMap;
$key1 = new stdClass;
$wm5[$key1] = "first";
$key2 = new stdClass;
$wm5[$key2] = "second";

unset($wm5[$key1]);
echo count($wm5), "\n";
echo isset($wm5[$key1]) ? "y" : "n", "\n";
echo isset($wm5[$key2]) ? "y" : "n", "\n";

foreach ($wm5 as $v) echo $v, " ";
echo "\n";

$wm6 = new WeakMap;
$o = new stdClass;
$wm6[$o] = 1;
$wm6[$o] = 2;
$wm6[$o] = 3;
echo count($wm6), "\n";
echo $wm6[$o], "\n";

$x = new stdClass;
$wr1 = WeakReference::create($x);
$wr2 = WeakReference::create($x);
echo ($wr1->get() === $wr2->get()) ? "same\n" : "diff\n";
