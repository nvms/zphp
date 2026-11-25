<?php
// __unserialize may set a readonly property once more, one with a default
// (php 8.6) included; afterwards it is readonly again
class WithDefaults {
    public readonly int $prop = 1;
    public public(set) readonly int $lock = 1;
    public readonly int $late;
    public function __unserialize(array $data): void {
        foreach ($data as $key => $value) {
            $this->{$key} = $value;
        }
        try {
            $this->prop = 9;
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}
$o = unserialize('O:12:"WithDefaults":2:{s:4:"prop";i:2;s:4:"late";i:5;}');
var_dump($o);
foreach (['prop', 'lock', 'late'] as $p) {
    try {
        $o->$p = 3;
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(unserialize('O:12:"WithDefaults":0:{}'));
