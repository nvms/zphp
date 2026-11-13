<?php
// a return inside try/finally ends the loops inside the try before the
// finally runs and the loops around it after: a finally that throws into a
// catch around the try leaves the outer loop running

function nested() {
    $array = [1, 2, 3];
    foreach ($array as $value) {
        echo "outer $value\n";
        try {
            try {
                foreach ($array as $_) {
                    return str_repeat("a", 2);
                }
            } finally {
                throw new Exception("from finally");
            }
        } catch (Exception $e) {
            echo "caught ", $e->getMessage(), "\n";
        }
    }
    return "loop done";
}
var_dump(nested());

function plain() {
    foreach ([1, 2] as $v) {
        try {
            try {
                return;
            } finally {
                throw new Exception;
            }
        } catch (Exception $e) {
            echo "plain caught $v\n";
        }
    }
    echo "plain end\n";
}
plain();

function returned() {
    foreach (['x', 'y'] as $outer) {
        foreach ([1, 2] as $inner) {
            try {
                return "$outer$inner";
            } finally {
                echo "finally $outer$inner\n";
            }
        }
    }
}
var_dump(returned());

function inFinally() {
    foreach ([1, 2] as $a) {
        try {
            return "try $a";
        } finally {
            foreach ([10, 20] as $b) {
                if ($b == 20) return "finally $a $b";
            }
        }
    }
}
var_dump(inFinally());

function gen() {
    yield 1;
    yield 2;
}
function overGenerator() {
    foreach ([1, 2] as $i) {
        try {
            foreach (gen() as $g) {
                try {
                    return $g;
                } finally {
                    echo "inner finally $i $g\n";
                }
            }
        } finally {
            echo "outer finally $i\n";
        }
    }
}
var_dump(overGenerator());

// a by-reference return returns the variable after the finally changed it
function &byRef(&$b) {
    $a =& $b;
    try {
        return $a;
    } finally {
        $a = 2;
    }
}
$x = 1;
$y =& byRef($x);
var_dump($y);
$x = 3;
var_dump($y);

function &undefinedThenSet() {
    try {
        return $a;
    } finally {
        $a = 'set in finally';
    }
}
var_dump(undefinedThenSet());
