<?php
function basic() {
    try {
        throw new Exception("boom");
    } catch (\Exception $e) {
        echo "caught: ", $e->getMessage(), "\n";
    } finally {
        echo "finally\n";
    }
}
basic();

function withReturn() {
    try {
        return "try";
    } finally {
        echo "finally1\n";
    }
}
echo withReturn(), "\n";

function finallyOverrides() {
    try {
        return "try";
    } finally {
        return "finally";
    }
}
echo finallyOverrides(), "\n";

function exceptionInTry() {
    try {
        throw new Exception("err");
    } finally {
        echo "f-runs\n";
    }
}
try { exceptionInTry(); } catch (\Exception $e) { echo "got: ", $e->getMessage(), "\n"; }

class FooErr extends \Exception {}
class BarErr extends \Exception {}

function multiCatch(string $which) {
    try {
        if ($which === "foo") throw new FooErr("from foo");
        if ($which === "bar") throw new BarErr("from bar");
        throw new \RuntimeException("other");
    } catch (FooErr | BarErr $e) {
        return "specific: " . get_class($e) . " - " . $e->getMessage();
    } catch (\Exception $e) {
        return "fallback: " . $e->getMessage();
    }
}
echo multiCatch("foo"), "\n";
echo multiCatch("bar"), "\n";
echo multiCatch("baz"), "\n";

function nestedFinally() {
    try {
        try {
            throw new Exception("inner");
        } finally {
            echo "inner-finally\n";
        }
    } catch (\Exception $e) {
        echo "outer-catch: ", $e->getMessage(), "\n";
    } finally {
        echo "outer-finally\n";
    }
}
nestedFinally();

function tryInFinally() {
    try {
        echo "try\n";
    } finally {
        try {
            echo "finally-try\n";
            throw new Exception("from-finally");
        } catch (\Exception $e) {
            echo "finally-caught: ", $e->getMessage(), "\n";
        }
    }
}
tryInFinally();

function rethrow() {
    try {
        throw new \RuntimeException("orig");
    } catch (\RuntimeException $e) {
        throw $e;
    }
}
try { rethrow(); } catch (\RuntimeException $e) { echo "rt: ", $e->getMessage(), "\n"; }

function chain() {
    try {
        try {
            throw new \RuntimeException("inner-msg");
        } catch (\RuntimeException $e) {
            throw new \LogicException("outer-msg", 0, $e);
        }
    } catch (\LogicException $e) {
        $prev = $e->getPrevious();
        echo "outer: ", $e->getMessage(), "\n";
        echo "prev-class: ", get_class($prev), "\n";
        echo "prev-msg: ", $prev->getMessage(), "\n";
    }
}
chain();

function deepChain() {
    $a = new Exception("A");
    $b = new Exception("B", 0, $a);
    $c = new Exception("C", 0, $b);
    return $c;
}
$e = deepChain();
echo $e->getMessage(), "\n";
echo $e->getPrevious()->getMessage(), "\n";
echo $e->getPrevious()->getPrevious()->getMessage(), "\n";
echo var_export($e->getPrevious()->getPrevious()->getPrevious(), true), "\n";

function exitsViaFinally() {
    $log = [];
    try {
        $log[] = "try-start";
        throw new Exception("e");
        $log[] = "after-throw";
    } catch (Exception $e) {
        $log[] = "caught: " . $e->getMessage();
        throw new RuntimeException("re-thrown");
    } finally {
        $log[] = "finally";
    }
    return $log;
}
try { exitsViaFinally(); } catch (\RuntimeException $e) { echo $e->getMessage(), "\n"; }

function counter() {
    $n = 0;
    try {
        for ($i = 0; $i < 3; $i++) {
            try {
                if ($i === 1) throw new Exception("at-1");
                $n += 10;
            } catch (Exception $e) {
                $n += 1;
            } finally {
                $n += 100;
            }
        }
        return $n;
    } finally {
        echo "outer-final\n";
    }
}
echo counter(), "\n";

function nopeCatch() {
    try {
        throw new \LogicException("x");
    } catch (\RuntimeException $e) {
        echo "should-not\n";
    }
}
try { nopeCatch(); } catch (\LogicException $e) { echo "le: ", $e->getMessage(), "\n"; }

class Custom extends \Exception {
    public function __construct(string $m, public readonly string $tag) {
        parent::__construct($m);
    }
}

try {
    throw new Custom("hello", "TAG-1");
} catch (\Exception $e) {
    if ($e instanceof Custom) echo "tag: ", $e->tag, "\n";
}

function trace() {
    try {
        throw new Exception("trace-me");
    } catch (\Exception $e) {
        return $e->getMessage();
    }
}
echo trace(), "\n";
