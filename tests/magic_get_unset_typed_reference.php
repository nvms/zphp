<?php
class Test {
    public $prop = "42";
    public int $val;
    public ?string $s;
    public function &__get($name) {
        echo "get $name\n";
        if ($name == 's') { $x = 5; return $x; }
        return $this->prop;
    }
}
class Plain {
    public int $val;
    public function __get($name) { return "7"; }
}
$p = new Plain; unset($p->val);
var_dump($p->val);
$test = new Test;
unset($test->val, $test->s);
var_dump($test->val);
var_dump($test);
$test->prop = "43";
$x = $test->val;
var_dump($x, $test);
var_dump($val = &$test->val);
var_dump($test);
$test->prop = "x";
var_dump($test, $val);
var_dump($test->s);
$test->prop = "abc";
try { var_dump($test->val); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
