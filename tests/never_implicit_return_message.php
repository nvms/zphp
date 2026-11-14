<?php
// a never-returning function that runs off its end names itself a method
// when it has a class scope

function f(): never
{
    if (false) throw new Exception;
}

class Foo
{
    public static function bar(): never
    {
        if (false) throw new Exception;
    }

    public function baz(): never
    {
        if (false) throw new Exception;
    }

    public function closure(): Closure
    {
        return function (): never {
            if (false) throw new Exception;
        };
    }
}

foreach ([fn() => f(), fn() => Foo::bar(), fn() => (new Foo)->baz(), (new Foo)->closure(), function (): never {}] as $call) {
    try {
        $call();
    } catch (TypeError $e) {
        echo preg_replace('/(\w+::)?\{closure:[^}]*\}/', '{closure}', $e->getMessage()), "\n";
    }
}
