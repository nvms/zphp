<?php
// calling a bound closure inside __call, more than once: each frame releases
// only the closure it ran
class C {
    public array $items = [10, 20];
    public static array $m = [];
    public function __call(string $name, array $args): mixed {
        $bound = self::$m[$name]->bindTo($this);
        return call_user_func_array($bound, $args);
    }
}
C::$m['has'] = function ($value) {
    foreach ($this->items as $item) {
        if ($item === $value) return true;
    }
    return false;
};
$c = new C;
var_dump($c->has(20));
var_dump($c->has(99));

class S {
    public static array $m = [];
    public function __call(string $name, array $args): mixed {
        $bound = Closure::bind(self::$m[$name], $this);
        return $bound(...$args);
    }
}
S::$m['f'] = function ($value) { return $value * 2; };
$s = new S;
var_dump($s->f(20));
var_dump($s->f(99));
