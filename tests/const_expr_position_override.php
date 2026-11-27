<?php
// code a constant expression calls reports the expression's file and line,
// and exceptions it creates trace from where the code really is
class S {
    public function __toString() {
        echo $undef;
        try {
            throw new Exception("inside");
        } catch (Exception $e) {
            echo $e->getLine(), "\n", $e->getTraceAsString(), "\n";
        }
        f();
        return "s";
    }
}
function f() {
    trigger_error("from f");
    $e = new Exception("f");
    echo $e->getLine(), "\n", $e->getTraceAsString(), "\n";
}
const S = new S();
class B {
    public $prop = "x" . S;
}
var_dump(new B());

class C {
    const K = "k" . S;
}
var_dump(C::K);

// an autoload clears the override
spl_autoload_register(function ($class) {
    $e = new Exception("autoload");
    echo $e->getLine(), "\n", $e->getTraceAsString(), "\n";
    eval("class $class { const V = 1; }");
});
class D {
    public $p = Missing::V . S;
}
var_dump(new D());

// thrown out of the expression
class T {
    public function __toString(): string {
        throw new Exception("thrown");
    }
}
const T = new T();
class E {
    public $p = "e" . T;
}
try {
    new E();
} catch (Exception $e) {
    echo $e->getLine(), "\n", $e->getTraceAsString(), "\n";
}
