<?php
// a generator a closure makes uses that closure object's static variables

function maker() {
    return function () {
        static $n = 0;
        yield ++$n;
        yield ++$n;
    };
}

$one = maker();
$two = maker();
foreach ([$one(), $one(), $two(), $one()] as $gen) {
    echo implode(',', iterator_to_array($gen, false)), "\n";
}

// a bound copy starts from the statics the original has then
$copy = Closure::bind($one, null, null);
echo implode(',', iterator_to_array($copy(), false)), "\n";
echo implode(',', iterator_to_array($one(), false)), "\n";

// plain functions and methods keep one set
function gen() {
    static $calls = 0;
    yield ++$calls;
}
class C {
    public function g() {
        static $k = 10;
        yield $k++;
    }
}
foreach ([gen(), gen()] as $g) foreach ($g as $v) echo $v, "\n";
$c = new C;
foreach ([$c->g(), (new C)->g()] as $g) foreach ($g as $v) echo $v, "\n";
