<?php
// closures and first-class callables in property defaults are made in the
// class's scope, and $closure->__invoke() calls the closure the way php's
// internal Closure::__invoke does
class Vault {
    public Closure $reveal = static function (Vault $v) { return $v->secret; };
    public Closure $hidden = self::hiddenMethod(...);

    public function __construct(private string $secret) {}

    private static function hiddenMethod(string $x) { return "hidden $x"; }
}
$v = new Vault('s3cret');
echo ($v->reveal)($v), "\n";
echo ($v->hidden)('call'), "\n";

class Other {
    private function nope() {}
}
class Prober {
    public Closure $bad = Other::nope(...);
}
try {
    new Prober();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

class A {}
class B {}
$typed = function (A $a) { return "ok"; };
echo $typed->__invoke(new A), "\n";
foreach ([fn () => $typed(new B), fn () => $typed->__invoke(new B), fn () => call_user_func([$typed, '__invoke'], new B)] as $attempt) {
    try {
        $attempt();
    } catch (TypeError $e) {
        echo preg_replace('/\{closure:[^}]*\}/', '{closure}', preg_replace('/ in \S+ on line \d+/', '', $e->getMessage())), "\n";
    }
}
