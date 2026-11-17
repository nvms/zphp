<?php
// a private abstract method a trait brings must be implemented by the class
// using the trait, even an abstract one

trait Fine {
    abstract private function done(int $a);
    abstract protected function later();
}

abstract class Implemented {
    use Fine;
    private function done(int $a) {}
}

class Child extends Implemented {
    protected function later() {}
}
echo get_class(new Child), "\n";

trait T {
    abstract private function method(int $a, string $b);
    abstract private function other();
}

abstract class C {
    use T;
}
