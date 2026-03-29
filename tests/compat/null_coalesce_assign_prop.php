<?php

class Config {
    public $cached = null;
    public $name = 'test';

    public function getValue() {
        return $this->cached ??= $this->compute();
    }

    private function compute() {
        return 'computed';
    }
}

$c = new Config();

// first call: cached is null, should compute and assign
echo $c->getValue() . "\n";

// second call: cached is set, should return cached value
echo $c->getValue() . "\n";

// ??= on non-null property should not re-assign
echo $c->name . "\n";
$c->name ??= 'overwritten';
echo $c->name . "\n";

// ??= on null property should assign
$c->cached = null;
$c->cached ??= 'new_value';
echo $c->cached . "\n";

// verify it works in a foreach without stack corruption
$items = ['a' => 1, 'b' => 2, 'c' => 3];
$configs = [];
foreach ($items as $key => $val) {
    $obj = new Config();
    $obj->cached ??= "cached_$key";
    $configs[$key] = $obj->cached;
}
echo implode(',', $configs) . "\n";
echo "count: " . count($configs) . "\n";
