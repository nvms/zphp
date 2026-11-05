<?php
// rethrowing an exception from finally links the pending one as previous,
// except where that would make the chain lead back into itself

try {
    $e = new Exception("Foo");
    try {
        throw new Exception("Bar", 0, $e);
    } finally {
        throw $e;
    }
} catch (Exception $caught) {
    var_dump($caught->getMessage(), $caught->getPrevious()?->getMessage());
    echo $caught, "\n";
}

try {
    $e = new Exception("Foo");
    try {
        throw new Exception("Bar", 0, $e);
    } finally {
        throw new Exception("Dummy", 0, $e);
    }
} catch (Exception $caught) {
    $chain = [];
    for ($x = $caught; $x; $x = $x->getPrevious()) $chain[] = $x->getMessage();
    echo implode(" <- ", $chain), "\n";
}

// a pending exception goes on the end of a chain that already exists
try {
    try {
        throw new Exception("pending");
    } finally {
        throw new Exception("outer", 0, new Exception("inner"));
    }
} catch (Exception $caught) {
    $chain = [];
    for ($x = $caught; $x; $x = $x->getPrevious()) $chain[] = $x->getMessage();
    echo implode(" <- ", $chain), "\n";
}
