<?php
// traces inside a fiber suspended within native code list its frames, then
// those of whoever resumed it, wherever that was; arguments survive the
// suspension; ReflectionFiber lists a suspended fiber's frames; a
// destructor run by a release may suspend the fiber it runs in

function show(array $trace) {
    foreach ($trace as $i => $t) {
        $args = isset($t['args']) ? implode(', ', array_map('json_encode', $t['args'])) : '';
        // a closure's name carries the file's path
        $function = preg_replace('/\{closure:.*:(\d+)\}/', '{closure:$1}', $t['function']);
        echo "  #$i ", $t['class'] ?? '', $t['type'] ?? '', $function, "($args)", isset($t['line']) ? " line {$t['line']}" : '', "\n";
    }
}

function inner($a, $b) {
    foreach ([1] as $v) {
        $got = Fiber::suspend("$a$b");
    }
    show(debug_backtrace());
    show((new Exception)->getTrace());
    return $got;
}

function gen($x) {
    yield inner($x, 'g');
}

$f = new Fiber(function (string $name) {
    foreach (gen($name) as $v) echo "yielded $v\n";
});

function starter($f) { return $f->start('n'); }
function resumer($f, $depth) { return $depth ? resumer($f, $depth - 1) : $f->resume('r'); }

echo "start: ", starter($f), "\n";
$r = new ReflectionFiber($f);
echo "suspended trace:\n";
show($r->getTrace());
echo "line ", $r->getExecutingLine(), "\n";
echo "resume from deeper:\n";
resumer($f, 3);

$f = new Fiber(function () {
    array_map(function ($x) {
        Fiber::suspend($x);
        show(debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS));
    }, [7]);
});
function deepStart($f, $n) { return $n ? deepStart($f, $n - 1) : $f->start(); }
deepStart($f, 4);
echo "resume from shallower:\n";
$f->resume();

class Dtor {
    function __construct(public string $name) {}
    function __destruct() {
        echo "destruct {$this->name}\n";
        $v = Fiber::suspend("from {$this->name}");
        echo "destructor resumed with $v\n";
    }
}
$f = new Fiber(function () {
    $o = new Dtor('a');
    unset($o);
    echo "after unset\n";
    $o = new Dtor('b');
    $o = null;
    echo "after null\n";
});
var_dump($f->start());
var_dump($f->resume('one'));
var_dump($f->resume('two'));
var_dump($f->isTerminated());
