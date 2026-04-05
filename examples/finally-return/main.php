<?php
// covers: try, finally, return, nested try-finally, catch-finally

// return from try with finally
function returnFromTry() {
    $log = [];
    try {
        $log[] = "try";
        return $log;
    } finally {
        echo "returnFromTry: finally\n";
    }
}
$r = returnFromTry();
echo "returnFromTry: " . implode(",", $r) . "\n";

// return from catch with finally
function returnFromCatch() {
    try {
        throw new Exception("err");
    } catch (Exception $e) {
        return "caught";
    } finally {
        echo "returnFromCatch: finally\n";
    }
}
echo "returnFromCatch: " . returnFromCatch() . "\n";

// nested try-finally with return
function nestedReturn() {
    try {
        try {
            return "deep";
        } finally {
            echo "nestedReturn: inner finally\n";
        }
    } finally {
        echo "nestedReturn: outer finally\n";
    }
}
echo "nestedReturn: " . nestedReturn() . "\n";

// try-finally without catch
function noCatch() {
    try {
        return "no catch";
    } finally {
        echo "noCatch: finally\n";
    }
}
echo "noCatch: " . noCatch() . "\n";

// return value is captured before finally runs
function returnBeforeFinally() {
    $x = "original";
    try {
        return $x;
    } finally {
        $x = "modified";
    }
}
echo "returnBeforeFinally: " . returnBeforeFinally() . "\n";

// normal flow still triggers finally
function normalFlow() {
    try {
        $val = "normal";
    } finally {
        echo "normalFlow: finally\n";
    }
    return $val;
}
echo "normalFlow: " . normalFlow() . "\n";

// exception flow still triggers finally
function exceptionFlow() {
    try {
        throw new Exception("boom");
    } catch (Exception $e) {
        $msg = $e->getMessage();
    } finally {
        echo "exceptionFlow: finally\n";
    }
    return $msg;
}
echo "exceptionFlow: " . exceptionFlow() . "\n";

// void return from try with finally
function voidReturn() {
    try {
        echo "voidReturn: try\n";
        return;
    } finally {
        echo "voidReturn: finally\n";
    }
}
voidReturn();

// finally runs even with early return in loop inside try
function loopReturn() {
    try {
        for ($i = 0; $i < 5; $i++) {
            if ($i == 2) return $i;
        }
    } finally {
        echo "loopReturn: finally\n";
    }
}
echo "loopReturn: " . loopReturn() . "\n";
