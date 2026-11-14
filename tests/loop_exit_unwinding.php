<?php
// break, continue and return leave the try blocks and loops they cross
// innermost first: a try's handler goes with it, a return's value is
// computed before any loop ends, and an exception from a loop's end is
// thrown where the loop ends, outside the tries inside it
function breakOut() {
    foreach ([1] as $x) {
        try { break; } catch (Exception $e) { echo "wrong1\n"; }
    }
    throw new Exception("break");
}
try { breakOut(); } catch (Exception $e) { echo "ok ", $e->getMessage(), "\n"; }

function breakWhile() {
    $n = 0;
    while (true) {
        try { break; } catch (Exception $e) { echo "wrong2\n"; if (++$n > 3) return; }
    }
    throw new Exception("while");
}
try { breakWhile(); } catch (Exception $e) { echo "ok ", $e->getMessage(), "\n"; }

function continueOut() {
    for ($i = 0; $i < 2; $i++) {
        try { continue; } catch (Exception $e) { echo "wrong3\n"; }
    }
    throw new Exception("continue");
}
try { continueOut(); } catch (Exception $e) { echo "ok ", $e->getMessage(), "\n"; }

function continueTwo() {
    foreach ([1, 2] as $a) {
        foreach ([3, 4] as $b) {
            try {
                echo "$a$b\n";
                continue 2;
            } finally {
                echo "finally $a$b\n";
            }
        }
    }
    throw new Exception("continue 2");
}
try { continueTwo(); } catch (Exception $e) { echo "ok ", $e->getMessage(), "\n"; }

function returnInsideCatchless() {
    try {
        try { return 1; } catch (Exception $e) { echo "wrong4\n"; }
    } finally {
        throw new Exception("from finally");
    }
}
try { returnInsideCatchless(); } catch (Exception $e) { echo "ok ", $e->getMessage(), "\n"; }

function thrower($x) { if ($x < 3) throw new Exception("t$x"); return $x; }
function retry() {
    foreach ([1, 2, 3] as $x) {
        try {
            return thrower($x);
        } catch (Exception $e) {
            echo "caught ", $e->getMessage(), "\n";
        }
    }
    return -1;
}
var_dump(retry());

class A {
    public $x = 1;
    function __destruct() { throw new Exception("destructor"); }
}
function loopEndThrows() {
    try {
        foreach ([new stdClass] as $x) {
            foreach (new A as $a) {
                try {
                    return $a;
                } catch (Exception $e) {
                    echo "wrong5\n";
                }
            }
        }
    } catch (Exception $e) {
        echo "ok ", $e->getMessage(), "\n";
    }
    return "after";
}
var_dump(loopEndThrows());

class D {
    function __construct(public $n) {}
    function __destruct() { echo "destroy {$this->n}\n"; }
}
function order() {
    foreach ([new D(1)] as $d) {
        $d = null;
        try {
            foreach ([new D(2)] as $d) {
                $d = null;
                try {
                    return value();
                } finally {
                    echo "finally inner\n";
                }
            }
        } finally {
            echo "finally outer\n";
        }
    }
}
function value() { echo "value\n"; return "v"; }
var_dump(order());

function returnInFinally() {
    foreach ([1] as $x) {
        try {
            try {
                return "first";
            } finally {
                foreach ([2] as $y) {
                    return "second";
                }
            }
        } finally {
            echo "outer finally\n";
        }
    }
}
var_dump(returnInFinally());

function generator() {
    try {
        try {
            yield 1;
            return 5;
        } catch (Exception $e) {
            echo "wrong6\n";
        }
    } finally {
        echo "generator finally\n";
    }
}
$g = generator();
foreach ($g as $v) echo "yield $v\n";
var_dump($g->getReturn());

function breakFinallyThrows() {
    try {
        foreach ([1, 2] as $x) {
            try {
                try {
                    break;
                } finally {
                    throw new Exception("finally in loop");
                }
            } catch (LogicException $e) {
                echo "wrong7\n";
            }
        }
    } catch (Exception $e) {
        echo "ok ", $e->getMessage(), "\n";
    }
}
breakFinallyThrows();
echo "done\n";
