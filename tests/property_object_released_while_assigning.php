<?php
// a typed property write whose coercion (__toString) drops the last holder
// of the object being written is refused (zend_std_write_property)
class A
{
    public string $prop;
    public $untyped;
    function __destruct() { echo "A destructed\n"; }
}
class B
{
    public function __toString()
    {
        global $a;
        $a = null;
        return str_repeat('a', 1);
    }
}

$a = new A();
try {
    $a->prop = new B();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
var_dump($a);

$a = new A();
$a->prop = '';
try {
    $a->prop = new B();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

// another holder keeps it: the write goes through
$a = new A();
$keep = $a;
$a->prop = new B();
var_dump($keep->prop, $a);
unset($keep);

// no coercion, no check
$a = new A();
$a->untyped = new B();
echo get_class($a->untyped), "\n";
echo "done\n";
