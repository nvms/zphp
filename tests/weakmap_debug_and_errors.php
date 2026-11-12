<?php
// var_dump shows a WeakMap's entries as key/value pairs; its dimension
// handlers take only object keys and can't append

$map = new WeakMap;
$a = new stdClass;
$b = new ArrayObject([1]);
$map[$a] = 'first';
$map[$b] = ['nested' => true];
var_dump($map);
print_r($map);
echo "\n";
var_dump((array) $map, get_object_vars($map));
unset($b);
var_dump(count($map));
var_dump($map);

foreach ([
    fn() => $map[1] = 2,
    fn() => $map[1],
    fn() => isset($map[1]),
    function () use ($map) { unset($map[1]); },
    fn() => $map[] = 1,
    fn() => $map[new stdClass],
    fn() => $map->offsetGet(new stdClass),
    fn() => $map->offsetExists('x'),
    fn() => new WeakReference,
] as $case) {
    try {
        var_dump($case());
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
var_dump(isset($map[$a]), $map[new stdClass] ?? 'default');
