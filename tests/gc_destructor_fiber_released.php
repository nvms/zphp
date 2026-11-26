<?php
// a destructor the collector runs inside a fiber suspends the gc's
// destructor fiber; when nothing else keeps that fiber it is destroyed
// right away, before the next garbage destructor runs

class Cycle {
    public static ?Throwable $pending = null;
    public static int $count = 0;
    public $self;
    public int $n = 0;

    public function __construct() {
        $this->self = $this;
    }

    public function __destruct() {
        $this->n = ++self::$count;
        echo "destruct {$this->n}\n";
        if (self::$pending === null) {
            try {
                Fiber::suspend();
            } finally {
                echo "finally {$this->n}\n";
                self::$pending = new RuntimeException("pending");
                throw self::$pending;
            }
        }
        throw new LogicException("thrown by {$this->n}", 0, self::$pending);
    }
}

$fiber = new Fiber(function () {
    new Cycle();
    new Cycle();
    try {
        gc_collect_cycles();
    } catch (Throwable $t) {
        for (; $t !== null; $t = $t->getPrevious()) {
            echo get_class($t), ": ", $t->getMessage(), "\n";
        }
    }
});
$fiber->start();

// a suspended destructor fiber the application keeps lives on
class Kept {
    public static ?Fiber $fiber = null;
    public $self;

    public function __construct() {
        $this->self = $this;
    }

    public function __destruct() {
        self::$fiber = Fiber::getCurrent();
        echo "kept suspends\n";
        Fiber::suspend();
        echo "kept resumed\n";
    }
}

$fiber = new Fiber(function () {
    new Kept();
    gc_collect_cycles();
    echo "collected\n";
});
$fiber->start();
var_dump(Kept::$fiber->isSuspended());
Kept::$fiber->resume();
var_dump(Kept::$fiber->isTerminated());
echo "end\n";
