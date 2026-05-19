<?php
// regression: 'new ClassName()' visibility-checks the constructor. previously
// zphp's 'new' opcode resolved __construct and called it without verifying
// the caller had visibility, so private/protected ctors (factory pattern,
// singletons, value-object-only-via-static-constructor) were silently
// callable from outside the class

class Factory {
    private function __construct(public string $name) {}
    public static function make(string $name): self { return new self($name); }
}
$f = Factory::make('via-factory');
echo $f->name . "\n";
try { new Factory('outside'); }
catch (\Error $e) { echo "priv: " . $e->getMessage() . "\n"; }

class Single {
    private static ?Single $i = null;
    private function __construct() {}
    public static function get(): self { return self::$i ??= new self; }
}
$a = Single::get();
$b = Single::get();
echo ($a === $b) ? "same\n" : "diff\n";
try { new Single; }
catch (\Error $e) { echo "single-priv: " . $e->getMessage() . "\n"; }

// protected ctor: callable from subclass
class Base {
    protected function __construct(public int $n) {}
    public static function make(int $n): self { return new static($n); }
}
class Derived extends Base {
    public static function makeChild(int $n): self { return new self($n); }
}
echo Base::make(1)->n . "\n";
echo Derived::makeChild(2)->n . "\n";
try { new Base(3); }
catch (\Error $e) { echo "proto: " . $e->getMessage() . "\n"; }

// public ctor unaffected
class Open {
    public function __construct(public string $v) {}
}
echo (new Open('open'))->v . "\n";
