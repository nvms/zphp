<?php
// a parent hook call can't be turned into a closure (a compile error)

class B {
    public mixed $x;
}
class C extends B {
    public mixed $x {
        set {
            $f = parent::$x::set(...);
            $f($value);
        }
    }
}

echo "not reached\n";
