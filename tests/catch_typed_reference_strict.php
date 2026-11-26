<?php
// a catch assigns its exception strictly (ZEND_CATCH): a typed reference
// the variable is bound to refuses it, even where a weak-mode assignment
// would have converted a Stringable exception to a string

class Test {
    public int $i = 42;
    public string $s = "str";
    public string|Exception $u = "union";
    public ?Throwable $t = null;
}

function attempt(string $label, Test $test, string $prop) {
    $ref =& $test->$prop;
    try {
        try {
            throw new Exception("ex");
        } catch (Exception $ref) {
            echo "$label: caught into the reference\n";
        }
    } catch (TypeError $e) {
        echo "$label: ", $e->getMessage(), "\n";
    }
    var_dump($test->$prop instanceof Exception ? get_class($test->$prop) : $test->$prop);
}

$test = new Test;
attempt('int', $test, 'i');
attempt('string', $test, 's');
attempt('union', $test, 'u');
attempt('nullable', $test, 't');

// at the top level too
$ref =& $test->s;
try {
    try {
        throw new RuntimeException("top");
    } catch (RuntimeException $ref) {
        echo "unreachable\n";
    }
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($test->s);

// a plain assignment still converts in weak mode
$ref = new class { public function __toString(): string { return "converted"; } };
var_dump($test->s);
