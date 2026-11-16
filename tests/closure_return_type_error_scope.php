<?php
// a closure's return type errors name it after its class scope

class Foo {
    public function make(): Closure {
        return function (): array {
            return null;
        };
    }

    public function none(): Closure {
        return function (): int {
            if (false) return 1;
        };
    }

    public static function stat(): Closure {
        return static fn(): string => 5.5 > 1 ? [] : '';
    }
}

$plain = function (): int {
    return 'x';
};

foreach ([(new Foo)->make(), (new Foo)->none(), Foo::stat(), $plain, Closure::bind($plain, null, Foo::class), (new Foo)->make()->bindTo(null, null)] as $f) {
    try {
        $f();
    } catch (TypeError $e) {
        echo preg_replace('/\{closure:[^}]*\}/', '{closure}', $e->getMessage()), "\n";
    }
}
