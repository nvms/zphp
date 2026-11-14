<?php
// extract() writing a variable that is a reference to a typed property
// follows the property's type

class Test {
    public int $i = 0;
    public string $s = "";
    public ?float $f = null;
}

$test = new Test;
$i = &$test->i;
$s = &$test->s;
$f = &$test->f;
try {
    extract(['i' => 'foo', 's' => 42]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($test->i, $test->s);
var_dump(extract(['s' => 42, 'f' => 3, 'i' => '17']));
var_dump($test->s, $test->f, $test->i);
try {
    extract(['f' => []]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($test->f);
