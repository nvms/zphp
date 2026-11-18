<?php
// $object->$name() sees what the calling scope sees: a private or protected
// method out of reach goes to __call, or is php's Error without one

class C {
    private function h() { return 'private'; }
    protected function p() { return 'protected'; }
    public function t($m) { return $this->$m(); }
}

class D extends C {
    public function u($m) { return $this->$m(); }
}

class Magic {
    private function secret() { return 'secret'; }
    public function __call($name, $args) { return "__call($name)"; }
}

$o = new D;
var_dump($o->t('h'), $o->u('p'), $o->t('p'));
foreach ([fn () => $o->{'h'}(), fn () => $o->u('h'), fn () => $o->{'p'}(), fn () => [$o, 'h']()] as $call) {
    try {
        $call();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
$m = new Magic;
$name = 'secret';
var_dump($m->$name(), [$m, 'secret'](), $m->secret());

// the scope is the running method's class, also when it runs through a
// closure made while another subclass was the called class
class Factory {
    private static $make;
    public function get() { return (self::$make ??= self::make(...))($this); }
    private static function make($container) { $method = 'build'; return $container->$method(); }
}
class FirstFactory extends Factory { protected static function build() { return 'first'; } }
class SecondFactory extends Factory { protected static function build() { return 'second'; } }
var_dump((new FirstFactory)->get(), (new SecondFactory)->get());
