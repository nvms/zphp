<?php
// destructors that run inside a fiber, and fibers started inside a
// destructor, which suspend within themselves

class StartsFiber {
    public function __construct(private string $name) {}
    public function __destruct() {
        echo "{$this->name}: destruct start\n";
        $inner = new Fiber(function () {
            echo "{$this->name}: inner fiber before suspend\n";
            $got = Fiber::suspend("{$this->name} suspended");
            echo "{$this->name}: inner fiber resumed with $got\n";
            return "{$this->name} done";
        });
        var_dump($inner->start());
        var_dump($inner->resume("value"));
        var_dump($inner->getReturn());
        echo "{$this->name}: destruct end\n";
    }
}

$outer = new Fiber(function () {
    new StartsFiber("in fiber");
    echo "outer fiber continues\n";
    $x = Fiber::suspend("outer suspended");
    echo "outer fiber resumed with $x\n";
    $o = new StartsFiber("unset in fiber");
    unset($o);
    return "outer done";
});

var_dump($outer->start());
new StartsFiber("main");
var_dump($outer->resume("again"));
var_dump($outer->getReturn());
echo "done\n";
