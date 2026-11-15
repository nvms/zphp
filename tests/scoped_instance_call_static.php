<?php
// A::m() from inside a subclass instance runs A::m on $this, so static::
// and get_called_class() name $this's class; a static method keeps A

class A {
    const T = "A";
    public function t() {
        echo static::T, " ", get_called_class(), " ", static::class, "\n";
    }
    public static function s() {
        echo "static ", static::T, "\n";
    }
    public function g() {
        yield static::T;
    }
}

class B extends A {
    const T = "B";
    public function t() {
        A::t();
        $c = "A";
        $c::t();
        $m = "t";
        A::$m();
        parent::t();
        A::s();
        foreach (A::g() as $v) echo "gen $v\n";
        call_user_func("A::t");
    }
}

class C extends B {
    const T = "C";
}

(new B)->t();
(new C)->t();

class Unrelated {
    public function x() {
        A::s();
        try {
            A::t();
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}
(new Unrelated)->x();
