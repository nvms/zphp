<?php
// regression: eval() returns the value produced by 'return <expr>' inside
// the eval'd code instead of always null. previously zphp's evalSource
// hardcoded a .null return, so any var_export-then-eval roundtrip pattern
// (common for cached config, set_state rebuilders) silently produced null
$r = eval('return 42;');
var_dump($r);

$r = eval('return "hello";');
var_dump($r);

$r = eval('return [1, 2, 3];');
var_dump($r);

// no return → null
$r = eval('$x = 1;');
var_dump($r);

// __set_state roundtrip via var_export
class Vec {
    public function __construct(public int $x = 0, public int $y = 0) {}
    public static function __set_state(array $arr): self { return new self($arr['x'], $arr['y']); }
}
$src = new Vec(3, 4);
$exp = var_export($src, true);
$rebuilt = eval('return ' . $exp . ';');
echo $rebuilt->x . "," . $rebuilt->y . "\n";
echo get_class($rebuilt) . "\n";

// expression returning an object directly
$r = eval('return new stdClass();');
echo get_class($r) . "\n";
