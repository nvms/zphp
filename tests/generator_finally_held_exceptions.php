<?php
// exceptions finally blocks hold survive a generator's suspension: a later
// exception takes them as its previous, and a generator destroyed there
// throws them (zend_dispatch_try_catch_finally_helper)
function chain(Throwable $e) {
    $parts = [];
    for (; $e; $e = $e->getPrevious()) $parts[] = get_class($e) . '(' . $e->getMessage() . ')';
    return implode(' <- ', $parts);
}

function nested() {
    try {
        throw new Exception('1');
    } finally {
        try {
            throw new Exception('2');
        } finally {
            try {
                yield;
            } finally {
                echo "inner finally\n";
            }
        }
    }
}
try {
    nested()->rewind();
} catch (Exception $e) {
    echo "destroyed: ", chain($e), "\n";
}

function thrower() {
    try {
        throw new Exception('held');
    } finally {
        try {
            yield 1;
        } finally {
            echo "finally runs\n";
            throw new Exception('in finally');
        }
    }
}
try {
    $g = thrower();
    $g->current();
    unset($g);
} catch (Exception $e) {
    echo "unset: ", chain($e), "\n";
}

function resumed() {
    try {
        throw new Exception('first');
    } finally {
        yield 1;
        throw new Exception('second');
    }
}
$g = resumed();
$g->current();
try {
    $g->next();
} catch (Exception $e) {
    echo "resumed: ", chain($e), "\n";
}

function caught() {
    try {
        try {
            throw new Exception('a');
        } finally {
            try {
                yield;
            } finally {
            }
        }
    } catch (Exception $e) {
        echo "caught inside: ", chain($e), "\n";
    }
    echo "after catch\n";
}
$g = caught();
$g->current();
try {
    unset($g);
    echo "no exception\n";
} catch (Exception $e) {
    echo "outside: ", chain($e), "\n";
}

function thrownInto() {
    try {
        throw new Exception('kept');
    } finally {
        yield 1;
    }
}
$g = thrownInto();
$g->current();
try {
    $g->throw(new Exception('thrown in'));
} catch (Exception $e) {
    echo "throw: ", chain($e), "\n";
}

function plain() {
    try {
        yield 1;
    } finally {
        echo "plain finally\n";
    }
}
$g = plain();
$g->current();
unset($g);
echo "done\n";
