<?php
// a nested write through an element offsetGet returns by reference makes
// that null element an array, appended or keyed
class AA implements ArrayAccess {
    public $data = [];
    public function &offsetGet($name): mixed {
        if (null === $name) return $this->data[];
        return $this->data[$name];
    }
    public function offsetSet($name, $value): void { $this->data[$name] = $value; }
    public function offsetUnset($name): void {}
    public function offsetExists($name): bool { return true; }
}
$aa = new AA;
$aa[3] = 1;
$aa[][][0] = 2;
$aa['k']['x'] = 3;
$aa['k']['y'][] = 4;
$aa[]['z'] = 5;
$aa[][] = 6;
var_dump($aa->data);
