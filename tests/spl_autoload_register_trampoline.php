<?php
// an autoloader is resolved where it is registered: a method that scope
// can't call goes through __call or __callStatic from then on
class Loader {
    public function __call($method, $args) {
        echo "__call($method, {$args[0]})\n";
    }
    public static function __callStatic($method, $args) {
        echo "__callStatic($method, {$args[0]})\n";
    }
    protected function load($class) {
        echo "load($class)\n";
    }
    protected static function loadStatic($class) {
        echo "loadStatic($class)\n";
    }
    public function registerInside() {
        spl_autoload_register([$this, 'load']);
    }
    public function trigger($class) {
        // the autoload happens inside the class, where load() is callable
        return class_exists($class);
    }
}

$l = new Loader;
spl_autoload_register([$l, 'load']);
spl_autoload_register(['Loader', 'loadStatic']);
var_dump($l->trigger('A1'));
var_dump(class_exists('A2'));
var_dump(count(spl_autoload_functions()));
foreach (spl_autoload_functions() as $f) {
    echo is_array($f) ? (is_object($f[0]) ? get_class($f[0]) : $f[0]) . '::' . $f[1] : 'other', "\n";
}
var_dump(spl_autoload_unregister(['Loader', 'loadStatic']));
var_dump($l->trigger('A3'));
var_dump(spl_autoload_unregister([$l, 'load']));
var_dump(spl_autoload_functions());

$m = new Loader;
$m->registerInside();
var_dump(class_exists('B1'));
var_dump($m->trigger('B2'));
