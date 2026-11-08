<?php
// a trait declared further down the file is bound at compile time, so a
// class above it can use it; a trait is no class to instantiate or read
// constants from
class UsesLater { use Later; }
trait Later { public $x = 1; const C = 2; function hi() { return 'hi'; } }
echo (new UsesLater)->hi(), UsesLater::C, "\n";
foreach ([fn () => new Later, fn () => Later::C, fn () => constant('Later::C'), fn () => (new ReflectionClass('Later'))->newInstance()] as $f) {
    try { $f(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
