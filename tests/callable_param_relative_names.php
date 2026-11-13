<?php
// a callable parameter takes "self::m", ["parent", "m"] and the like as
// zend_is_callable resolves them in the callee's scope, with their
// deprecations

set_error_handler(function ($no, $msg, $file, $line) {
    echo "[$no] $msg (line $line)\n";
    return true;
});

class A {
    public static function foo() {}
    private static function secret() {}
}
class B extends A {
    public static function own() {}
    function test() {
        foreach (["self::own", "parent::foo", "static::own", ["self", "own"], ["parent", "foo"], ["static", "own"],
                  ["B", "parent::foo"], [$this, "A::foo"], "A::foo", "A::secret", "self::missing", ["nope", "x"], "B::own"] as $c) {
            try {
                $this->hint($c);
            } catch (TypeError $e) {
                echo $e->getMessage(), "\n";
            }
        }
    }
    function hint(callable $c) { echo json_encode($c), " ok\n"; }
}
(new B)->test();

function outside(callable $c) { echo "outside ok\n"; }
foreach (["A::foo", "self::foo", "A::secret", ["A", "foo"]] as $c) {
    try {
        outside($c);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
