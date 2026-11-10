<?php
// first-class callables resolve what they name when they are made: errors
// then, namespace fallback, and self/parent/static of the making scope
namespace App;

function local($x) { return "local $x"; }

class Base {
    public static function who() { return static::class; }
    public function inst() { return "inst of " . static::class; }
}
class Child extends Base {
    public function callables() {
        return [self::who(...), parent::who(...), static::who(...), Base::inst(...), $this->inst(...)];
    }
    private function hidden() { return "hidden"; }
    public function hiddenCallable() { return $this->hidden(...); }
}
class GrandChild extends Child {}

echo strlen(...)("abcd"), "\n";
echo local(...)(1), "\n";
echo \strtoupper(...)("up"), "\n";
foreach ((new GrandChild)->callables() as $c) {
    echo $c(), "\n";
}
echo (new Child)->hiddenCallable()(), "\n";

$closure = function () { return "same"; };
var_dump($closure(...) === $closure);
var_dump(strlen(...) == strlen(...), strlen(...) === strlen(...));
$o = new Child;
var_dump($o->inst(...) == $o->inst(...), $o->inst(...) == (new Child)->inst(...));

$attempts = [
    fn () => nope(...),
    fn () => (new Child)->nope(...),
    fn () => Child::nope(...),
    fn () => Base::inst(...),
    fn () => (new Child)->hidden(...),
    function () { $n = 5; return $n(...); },
    function () { $s = 'App\local'; return $s(...); },
];
foreach ($attempts as $attempt) {
    try {
        $made = $attempt();
        echo "made ", get_class($made), "\n";
    } catch (\Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
