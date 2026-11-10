<?php
// at shutdown php destroys what is left in handle order: objects get their
// destructors, waiting generators and suspended fibers run their finally
// blocks

register_shutdown_function(function () {
    echo "shutdown function\n";
});

class Named {
    function __construct(public $name) {}
    function __destruct() {
        echo "{$this->name} destructed\n";
    }
}

$first = new Named("first");

function waiting() {
    try {
        yield 1;
    } finally {
        echo "generator finally\n";
    }
}
$gen = waiting();
$gen->current();

$fiber = new Fiber(function () {
    try {
        Fiber::suspend();
    } finally {
        echo "fiber finally\n";
    }
});
$fiber->start();

$keep = [$gen, $fiber];
$last = new Named("last");

$nested = new Fiber(function () {
    $inner = new Fiber(function () {
        try {
            Fiber::suspend();
        } finally {
            echo "inner fiber finally\n";
        }
    });
    $inner->start();
    try {
        Fiber::suspend();
    } finally {
        echo "outer fiber finally\n";
    }
});
$nested->start();
echo "end of script\n";
