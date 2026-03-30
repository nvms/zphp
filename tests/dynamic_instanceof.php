<?php
interface Loggable {}
class Base implements Loggable {}
class Child extends Base {}

$obj = new Child();

// static instanceof
echo ($obj instanceof Loggable) ? "1" : "0";
echo ($obj instanceof Base) ? "1" : "0";
echo ($obj instanceof Child) ? "1" : "0";
echo "\n";

// dynamic instanceof with variable
$iface = 'Loggable';
$base = 'Base';
$child = 'Child';
$fake = 'NonExistent';

echo ($obj instanceof $iface) ? "1" : "0";
echo ($obj instanceof $base) ? "1" : "0";
echo ($obj instanceof $child) ? "1" : "0";
echo ($obj instanceof $fake) ? "1" : "0";
echo "\n";

// dynamic instanceof with expression
$classes = ['Loggable', 'Base', 'Child', 'stdClass'];
foreach ($classes as $cls) {
    echo ($obj instanceof $cls) ? "1" : "0";
}
echo "\n";

// dynamic instanceof with array access
$types = ['t' => 'Base'];
echo ($obj instanceof $types['t']) ? "1" : "0";
echo "\n";
