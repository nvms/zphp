<?php
// unserialize_callback_func is resolved as call_user_function does: in the
// calling scope, refusing what that scope can't call
class Tester {
    private static function hidden($name) { echo "hidden($name)\n"; eval("class $name {}"); }
    public static function run(string $s) { return unserialize($s); }
}
class Parent_ {
    public static function cb($name) { echo "Parent_::cb($name)\n"; eval("class $name {}"); }
}
class Child extends Parent_ {
    public static function cb($name) { echo "Child::cb($name)\n"; }
    public function run(string $s) { return unserialize($s); }
}

function attempt(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

ini_set('unserialize_callback_func', 'Tester::hidden');
attempt(fn() => unserialize('O:3:"AAA":0:{}'));
attempt(fn() => Tester::run('O:3:"BBB":0:{}'));

ini_set('unserialize_callback_func', "nope\0more");
attempt(fn() => unserialize('O:3:"CCC":0:{}'));

ini_set('unserialize_callback_func', 'parent::cb');
attempt(fn() => unserialize('O:3:"DDD":0:{}'));
attempt(fn() => (new Child)->run('O:3:"EEE":0:{}'));

function cb_changes($name) {
    ini_set('unserialize_callback_func', 'cb_other_name_entirely');
}
ini_set('unserialize_callback_func', 'cb_changes');
attempt(fn() => unserialize('O:3:"FFF":0:{}'));
var_dump(ini_get('unserialize_callback_func'));
