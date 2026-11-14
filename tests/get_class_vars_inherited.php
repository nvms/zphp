<?php
// get_class_vars lists inherited properties after the class's own, statics
// after instance ones, each as visible from the calling scope
class A {
    public $a = 1;
    protected $pa = 'pa';
    private $b = 2;
    public static $sa = 'sa';
    private static $psa = 'psa';
}
class B extends A {
    public $own = 3;
    private $b = 'B b';
    protected static $sb = 'sb';
    public function vars($of) { return get_class_vars($of); }
    public static function svars($of) { return get_class_vars($of); }
}
class C extends B {
    public $a = 'redeclared';
    public function vars2($of) { return get_class_vars($of); }
}
interface I { const X = 1; }

var_dump(get_class_vars('A'), get_class_vars('B'), get_class_vars('C'));
$b = new B;
var_dump($b->vars('A'), $b->vars('B'), $b->vars('C'), B::svars('c'));
var_dump((new C)->vars2('B'));
var_dump(get_class_vars('I'));
try {
    get_class_vars('Missing');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
spl_autoload_register(function ($c) {
    echo "autoload $c\n";
    if ($c === 'Late') { eval('class Late { public $x = 5; }'); }
});
var_dump(get_class_vars('Late'));
