<?php
// a constant expression doesn't run user code through [] on an object or
// unpack anything but an array

enum Suit implements ArrayAccess {
    case Hearts;

    public function offsetGet($key): mixed { return 42; }
    public function offsetExists($key): bool { return true; }
    public function offsetSet($key, $value): void {}
    public function offsetUnset($key): void {}
}

class X {
    const DIM = Suit::Hearts[0];
    const LIST = [1, 2, 3][1];
    const SPREAD = [...[1, 2], ...['a' => 3]];
}

var_dump(X::LIST, X::SPREAD);
try {
    var_dump(X::DIM);
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

function withDefault($a = Suit::Hearts['x'], $b = [...new ArrayObject([1])]) {
    return [$a, $b];
}
try {
    withDefault();
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    withDefault(1);
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
var_dump(withDefault(1, 2));
