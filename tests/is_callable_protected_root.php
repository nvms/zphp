<?php
// is_callable() sees a protected method from a class related to the one that
// first declared it, as a call does; a private ancestor starts a new chain
class A {
    protected static function ma() { return 'A::ma()'; }
    private static function mp() { return 'A::mp()'; }
    protected function inst() { return 'A::inst()'; }
}
class B1 extends A {
    protected static function ma() { return 'B1::ma()'; }
    protected static function mp() { return 'B1::mp()'; }
    protected static function mb() { return 'B1::mb()'; }
    protected function inst() { return 'B1::inst()'; }
}
class B2 extends A {
    public static function test() {
        foreach (['A::ma', 'A::mp', 'B1::ma', 'B1::mp', 'B1::mb'] as $c) {
            echo $c, ': ', var_export(is_callable($c), true), "\n";
        }
        $b1 = new B1;
        var_dump(is_callable([$b1, 'inst']), is_callable([new B1, 'mb']));
        var_dump(call_user_func('B1::ma'), call_user_func([$b1, 'inst']));
        try {
            call_user_func('B1::mp');
        } catch (Error $e) {
            echo get_class($e), ': ', $e->getMessage(), "\n";
        }
    }
}
B2::test();
var_dump(is_callable('B1::ma'));
