<?php
// a default of self::class is the class name itself, which php prints as a
// string in an incompatible declaration

abstract class Foo
{
    function bar($a = self::class) {}
}

trait T {
    public function bar() {
    }
}

class B extends Foo
{
    use T;
}
