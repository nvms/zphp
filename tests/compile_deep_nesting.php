<?php
// source nested as deep as php's parser takes compiles and runs, whatever
// the stack it compiles on: the main one, a fiber's
function depthOf($v) {
    $d = 0;
    while (is_array($v) && $v !== []) {
        $v = $v[0];
        $d++;
    }
    return $d;
}

function f($x = 0) {
    return $x + 1;
}

$cases = [
    'arrays' => 'return ' . str_repeat('[', 9993) . str_repeat(']', 9993) . ';',
    'parentheses' => 'return ' . str_repeat('(', 9993) . '1' . str_repeat(')', 9993) . ';',
    'negations' => 'return ' . str_repeat('!', 9995) . 'true;',
    'casts' => 'return ' . str_repeat('(int)', 9000) . '"7";',
    'nested calls' => 'return ' . str_repeat('f(', 4996) . str_repeat(')', 4996) . ';',
    'nested closures' => 'return ' . str_repeat('(function () { return ', 600) . '1' . str_repeat('; })()', 600) . ';',
    'nested arrow functions' => '$a = 5; return ' . str_repeat('(fn() => ', 900) . '$a' . str_repeat(')()', 900) . ';',
    'nested ternaries' => '$a = 1; return ' . str_repeat('$a ? (', 1900) . '"deep"' . str_repeat(') : 0', 1900) . ';',
    'nested matches' => '$a = 1; return ' . str_repeat('match ($a) { 1 => ', 1200) . '"matched"' . str_repeat(', default => 0 }', 1200) . ';',
    'nested ifs' => '$a = 1; ' . str_repeat('if ($a) { ', 1600) . 'return "inside";' . str_repeat(' }', 1600),
    'deep blocks' => str_repeat('{', 4900) . '$x = "block";' . str_repeat('}', 4900) . ' return $x;',
    'elseif chain' => '$a = 2000; if ($a === 0) { return 0; }' . implode('', array_map(fn($i) => " elseif (\$a === $i) { return $i; }", range(1, 2000))) . ' else { return -1; }',
    'constant array' => 'const DEEP = ' . str_repeat('[', 9990) . str_repeat(']', 9990) . '; return DEEP;',
    'parameter default' => 'function g($x = ' . str_repeat('[', 9980) . str_repeat(']', 9980) . ') { return $x; } return g();',
    'dimension chain' => '$a = []; return $a' . str_repeat('[0]', 20000) . ' ?? "missing";',
    'nullsafe chain' => '$a = null; return $a' . str_repeat('?->p', 2000) . ' ?? "null";',
];

function show($label, $r) {
    if (is_array($r)) {
        echo $label, ": array nested ", depthOf($r), " deep\n";
    } else {
        echo $label, ": ", var_export($r, true), "\n";
    }
}

foreach ($cases as $label => $code) {
    show($label, eval($code));
}

// the same on a fiber's stack, one php's fibers get from fiber.stack_size
// (16M holds the arrays for php; zphp's frames are larger than that)
ini_set('fiber.stack_size', '16M');
$fiber = new Fiber(function () use ($cases) {
    foreach (['arrays', 'parentheses', 'nested calls', 'deep blocks', 'constant array'] as $label) {
        show("$label in a fiber", eval(str_replace('DEEP', 'DEEP_IN_FIBER', $cases[$label])));
    }
    // and from inside callbacks a native runs, each on the fiber's stack
    $recurse = function ($n) use (&$recurse, $cases) {
        if ($n > 0) return array_map($recurse, [$n - 1])[0];
        return eval($cases['arrays']);
    };
    show('arrays under 10 callbacks', $recurse(10));
    Fiber::suspend('suspended');
    show('arrays after a resume', eval($cases['arrays']));
});
echo $fiber->start(), "\n";
$fiber->resume();
echo $fiber->isTerminated() ? "fiber done\n" : "fiber running\n";

// a configured zend.max_allowed_stack_size is enforced, as php does: a walk
// past it is php's compile error, never more stack
$configured = [
    ['64K', '$test' . str_repeat('->p', 500) . ';'],
    ['64K', '$test' . str_repeat('->f()', 500) . ';'],
    ['64K', '$test = [' . str_repeat('~', 7600) . '1];'],
    ['512K', '$test = [' . str_repeat('~', 7600) . '1];'],
    ['512K', '$x = ' . str_repeat('[', 5000) . str_repeat(']', 5000) . ';'],
];
foreach ($configured as [$size, $code]) {
    $cmd = escapeshellarg(PHP_BINARY) . " -d zend.max_allowed_stack_size=$size -d display_errors=1 -d log_errors=0 -d html_errors=0 -r "
        . escapeshellarg('echo "start\n"; ' . $code . ' echo "end\n";') . ' 2>&1';
    $out = [];
    exec($cmd, $out, $status);
    echo "with $size: ", trim(implode("\n", $out)), "\nexit status $status\n";
}
