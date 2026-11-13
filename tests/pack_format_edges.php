<?php
// pack() as php's pack.c builds its output: repeaters, '*', padding, the
// position codes, conversions of its arguments, and its warnings and errors

class S { function __toString(): string { return "obj"; } }
$cases = [
    ['a5', 'ab'], ['A5', 'ab'], ['Z5', 'ab'], ['Z*', 'ab'], ['a*', 'abc'], ['A*', 12], ['Z0', 'x'], ['Z1', 'x'],
    ['a2', new S], ['H*', 'abc'], ['h*', '1f2'], ['H3', 'abcdef'], ['H5', 'ab'], ['H*', 'xyz'], ['h0', 'ab'],
    ['C3', 1, 2, 3], ['c*', -1, 256, 257], ['n', 0x1234], ['v', 0x1234], ['N', -1], ['V', 1.9], ['J', 1],
    ['P', -2], ['q', 1e20], ['Q', -1e20], ['s', 70000], ['S*', 1, '2', true], ['l', '12abc'], ['g', 1.5],
    ['G', -2.25], ['e', 0.1], ['E', 1e300], ['f', 'x'], ['d', 3], ['x3'], ['X'], ['X5'], ['@3'], ['a3@1'],
    ['C2X@4C', 1, 2, 3], ['x*'], ['@*'], ['C', 1, 2, 3], ['a', []], ['nvc*', 1, 2, 3, 4], [''], ['C0', 5],
];
foreach ($cases as $c) {
    $f = array_shift($c);
    echo json_encode($f), ': ';
    try {
        echo bin2hex(pack($f, ...$c)), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
foreach ([['C'], ['a'], ['Y'], ['C2', 1], ['E2E2147483647H*', 0, 0, 0], ['C2147483647', 1]] as $c) {
    $f = array_shift($c);
    try {
        pack($f, ...$c);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
