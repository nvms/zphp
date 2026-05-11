<?php
function f1() {
    try { return 1; } finally { echo "f1 finally\n"; }
}
echo f1(), "\n";

function f2() {
    try { return 1; } finally { return 2; }
}
echo f2(), "\n";

function f3() {
    try { throw new Exception("boom"); } finally { echo "f3 finally\n"; }
}
try { f3(); } catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }

function f5() {
    for ($i = 0; $i < 3; $i++) {
        try {
            if ($i === 1) break;
            echo "iter $i\n";
        } finally {
            echo "fin $i\n";
        }
    }
}
f5();

function f6() {
    for ($i = 0; $i < 5; $i++) {
        try {
            if ($i % 2 === 0) continue;
            echo "odd $i\n";
        } finally {
            echo "f6fin $i\n";
        }
    }
}
f6();

function g7() {
    try {
        yield 1;
        yield 2;
    } finally {
        echo "g7 finally\n";
    }
}
foreach (g7() as $v) echo "g7: $v\n";

function g8() {
    try {
        yield 1;
        throw new Exception("g8 boom");
        yield 2;
    } finally {
        echo "g8 finally\n";
    }
}
try {
    foreach (g8() as $v) echo "g8: $v\n";
} catch (Exception $e) { echo "g8 caught: ", $e->getMessage(), "\n"; }

function f9() {
    try {
        try {
            throw new Exception("inner");
        } finally {
            echo "f9 inner finally\n";
        }
    } catch (Exception $e) {
        echo "f9 caught: ", $e->getMessage(), "\n";
    } finally {
        echo "f9 outer finally\n";
    }
}
f9();

function f10() {
    $x = 1;
    try {
        $x = 2;
        return $x;
    } finally {
        $x = 3;
    }
}
echo f10(), "\n";

function f11() {
    try { return 10; } catch (Exception $e) { return 20; } finally { echo "f11 finally\n"; }
}
echo f11(), "\n";

function f12() {
    try {
        throw new Exception("e");
    } catch (Exception $e) {
        throw new RuntimeException("rethrow");
    } finally {
        echo "f12 finally\n";
    }
}
try { f12(); } catch (Exception $e) { echo "f12: ", $e->getMessage(), "\n"; }

function f13() {
    $i = 0;
    try { $i = 100; } finally { echo "$i\n"; }
}
f13();

function f14() {
    try {
        throw new Exception("inner");
    } finally {
        throw new Exception("outer");
    }
}
try { f14(); } catch (Exception $e) {
    echo "f14: ", $e->getMessage(), "\n";
    if ($e->getPrevious()) echo "prev: ", $e->getPrevious()->getMessage(), "\n";
}
