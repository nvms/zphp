<?php
class K {
    public function __construct(public string $name) {}
}
$s = new SplObjectStorage;
$a = new K("a"); $b = new K("b"); $c = new K("c");
$s[$a] = "va"; $s[$b] = "vb"; $s[$c] = "vc";

$un = unserialize(serialize($s));
echo $un->count(), "\n";
foreach ($un as $k) echo $k->name, "=", $un[$k], " ";
echo "\n";

foreach ($un as $k) {
    echo isset($un[$k]) ? "y" : "n";
}
echo "\n";

$keys = [];
foreach ($un as $k) $keys[] = $k;
$un->offsetUnset($keys[1]);
echo $un->count(), "\n";
foreach ($un as $k) echo $k->name, " ";
echo "\n";
