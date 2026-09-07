<?php
namespace CallbackScope;

class Promise {
    private function settle($value) { echo "settled:$value\n"; }
    public function resolver() {
        $target = $this;
        return static function ($value) use (&$target) {
            $target->settle($value);
        };
    }
}
class Executor {
    public function run($callback) { $callback('direct'); }
    public function native($callback) { call_user_func($callback, 'native'); }
}
$callback = (new Promise())->resolver();
(new Executor())->run($callback);
(new Executor())->native($callback);

class Base {
    private static function secret() { return 'base'; }
    public static function callbacks() {
        $value = 'value';
        return [
            static function () { return self::secret() . ':' . static::class; },
            static function () use (&$value) { return self::secret() . ':' . static::class . ':' . $value; },
            static function () use ($value) { return self::secret() . ':' . static::class . ':' . $value; },
            static fn () => self::secret() . ':' . static::class,
            function () { return static function () { return self::secret() . ':' . static::class; }; },
        ];
    }
}
class Child extends Base {}
foreach ([Base::callbacks(), Child::callbacks()] as $callbacks) {
    foreach ($callbacks as $i => $cb) {
        if ($i === 4) $cb = $cb();
        echo $cb(), "\n";
        echo call_user_func($cb), "\n";
    }
}

// Global callbacks/functions must not borrow an invoking method's privilege.
function outsider($object) { return $object->secret(); }
class Vault {
    private function secret() { return 'leaked'; }
    public function invoke($cb) {
        try { echo $cb($this), "\n"; }
        catch (\Error $e) { echo "denied\n"; }
    }
}
$vault = new Vault();
$vault->invoke(static function ($object) { return $object->secret(); });
$vault->invoke(function ($object) { return $object->secret(); });
$vault->invoke(__NAMESPACE__ . '\\outsider');
