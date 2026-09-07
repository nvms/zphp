<?php
class ArrayOwned {
    public function __construct(public string $name) {}
    public function __destruct() { echo "released:$this->name\n"; }
}
$a = ['first' => new ArrayOwned('shift'), 'other' => 2];
$item = array_shift($a);
var_dump(array_keys($a));
unset($item);
$a = ['first' => new ArrayOwned('splice'), 'last' => 3];
$removed = array_splice($a, 0, 1, [new ArrayOwned('replacement')]);
var_dump(array_keys($a), array_keys($removed));
unset($removed, $a);
foreach ([new ArrayObject(), new ArrayIterator()] as $container) {
    $container['key'] = new ArrayOwned('container');
    unset($container['key']);
    var_dump(isset($container['key']));
}
$value = 4;
$a = ['a' => 2];
$a['z'] = &$value;
ksort($a);
$a['z'] = 8;
var_dump($value, array_keys($a));
$b = [1, 2, 3];
array_splice($b, 1, 1, $b);
var_dump($b);
