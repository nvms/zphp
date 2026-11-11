<?php
// a generator's frame keeps its call's context: the class a static method
// was called through, the arguments past its parameters, and the last value
// of a delegate that returned

class Test {
    public static function gen() {
        var_dump(get_called_class());
        var_dump(static::class);
        yield 1;
    }
}
class Extended extends Test {
}
foreach (Extended::gen() as $v) {
    var_dump($v);
}

function args($first) {
    var_dump(func_get_args());
    yield;
}
$g = args("a", "b", "c");
$g->rewind();

function inner() {
    yield from [1, 2, 3];
}
function outer($g) {
    yield from $g;
}
$gen = inner();
$outers = [outer($gen), outer($gen)];
do {
    foreach ($outers as $o) {
        var_dump($o->current());
        $gen->next();
    }
} while ($gen->valid());
