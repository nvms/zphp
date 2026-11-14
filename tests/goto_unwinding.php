<?php
// goto leaves loops and try blocks as php's zend_resolve_goto_label does:
// a foreach frees its iterable, a try drops its handler and runs its
// finally, innermost first; a goto into a try block runs under its handler
class A {
    function __construct(public $n) {}
    function __destruct() { echo "destruct{$this->n}\n"; }
}

function outOfTry() {
    try {
        goto out;
    } catch (Exception $e) {
        echo "wrongly caught\n";
    }
    out:
    throw new Exception("after");
}
try { outOfTry(); } catch (Exception $e) { echo "outer caught ", $e->getMessage(), "\n"; }

function outOfFinally() {
    try {
        try {
            goto label;
        } finally {
            echo "finally1\n";
        }
    } finally {
        echo "finally2\n";
    }
    label:
    echo "label\n";
}
outOfFinally();

function outOfCatch() {
    try {
        throw new Exception("e");
    } catch (Exception $e) {
        echo "caught\n";
        goto done;
    } finally {
        echo "finally\n";
    }
    done:
    echo "done\n";
}
outOfCatch();

function outOfLoops() {
    foreach ([new A(1)] as $a) {
        $a = null;
        try {
            foreach ([new A(2)] as $a) {
                $a = null;
                try {
                    foreach ([new A(3)] as $a) {
                        $a = null;
                        goto out;
                    }
                } finally {
                    echo "finally1\n";
                }
                out: ;
            }
        } finally {
            echo "finally2\n";
        }
    }
    echo "end\n";
}
outOfLoops();

function backward() {
    $i = 0;
    again:
    foreach ([new A(10 + $i)] as $a) {
        $a = null;
        try {
            if (++$i < 3) goto again;
        } finally {
            echo "finally $i\n";
        }
    }
    echo "i=$i\n";
}
backward();

function intoTry() {
    goto a;
    try {
        echo "skipped\n";
        a:
        echo "in try\n";
        throw new Exception("x");
    } catch (Exception $e) {
        echo "caught in intoTry\n";
    }
    goto b;
    try {
        throw new Exception("y");
    } catch (Exception $e) {
        echo "skipped too\n";
        b:
        echo "in catch\n";
    }
    echo "end intoTry\n";
}
intoTry();

function intoTryWithFinally() {
    goto inside;
    try {
        echo "skipped\n";
        inside:
        echo "inside\n";
    } finally {
        echo "finally ran\n";
    }
    echo "after\n";
}
intoTryWithFinally();

function backwardIntoTry() {
    $n = 0;
    try {
        back:
        $n++;
        if ($n > 2) throw new Exception("n=$n");
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
        return;
    }
    goto back;
}
backwardIntoTry();

function insideFinally() {
    try {
        echo "try\n";
    } finally {
        $k = 0;
        loop:
        if (++$k < 3) goto loop;
        echo "k=$k\n";
    }
}
insideFinally();

// many gotos out of a try must not pile up handlers
function manyTimes() {
    $i = 0;
    top:
    try {
        if (++$i < 100000) goto top;
    } finally {
    }
    echo "loops: $i\n";
}
manyTimes();
echo "done\n";
