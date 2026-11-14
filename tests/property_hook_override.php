<?php
// #[\Override] on a property hook needs an inherited property that can
// already be read (get) or written (set)
class P { public $a; public $v { get => 0; } }
class C extends P {
    public $a {
        #[\Override] get => 1;
        #[\Override] set { echo "set a\n"; }
    }
    public $v {
        #[\Override] get => 2;
    }
}
interface I { public $b { get; } }
class D implements I {
    public $b {
        #[\Override] get => 3;
    }
}
$c = new C;
echo $c->a, $c->v, (new D)->b, "\n";
$c->a = 5;
ini_set('fatal_error_backtraces', '0');
eval('class E extends P { public $v { get => 4; #[\Override] set {} } }');
echo "not reached\n";
