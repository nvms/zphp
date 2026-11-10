<?php
// a generator destroyed before it finishes runs the finally blocks around
// where it waits, skipping catch blocks (php's zend_generator_dtor_storage);
// a yield there is an Error, an exception thrown there reaches the code that
// released the generator, and the generator it delegates to goes first

function nested() {
    try {
        try {
            yield 1;
        } catch (Throwable $e) {
            echo "never caught ", get_class($e), "\n";
        } finally {
            echo "inner finally\n";
        }
        echo "never after inner\n";
    } finally {
        echo "outer finally\n";
    }
}
$g = nested();
$g->current();
unset($g);

function throwing() {
    try {
        yield 1;
    } finally {
        echo "finally throws\n";
        throw new Exception("from finally");
    }
}
$g = throwing();
$g->current();
try {
    unset($g);
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), ", previous ", var_export($e->getPrevious(), true), "\n";
}

function yields_again() {
    try {
        yield 1;
    } finally {
        try {
            yield 2;
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
        echo "after\n";
    }
}
$g = yields_again();
$g->current();
unset($g);

class Dtor {
    function __destruct() { echo "Dtor\n"; }
}
function holds_operands() {
    try {
        var_dump(new Dtor, yield);
    } finally {
        echo "operand finally\n";
    }
}
$g = holds_operands();
$g->rewind();
unset($g);

function inner() {
    try {
        yield 1;
        return true;
    } finally {
        echo "inner generator finally\n";
    }
}
function outer() {
    try {
        var_dump(yield from inner());
    } finally {
        echo "outer generator finally\n";
    }
}
$g = outer();
$g->current();
unset($g);

function shared() {
    yield 42;
}
function delegates($g) {
    yield from $g;
}
$s = shared();
var_dump(delegates($s)->current());
var_dump(delegates($s)->current());

function kept() {
    try {
        yield 1;
        yield 2;
    } finally {
        echo "kept finally\n";
    }
}
$g = kept();
foreach ($g as $v) {
    break;
}
echo "loop left, generator alive\n";
var_dump($g->current());
$g = null;
echo "done\n";
