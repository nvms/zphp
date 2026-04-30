<?php

// basic newLazyGhost: initializer fires on first property access
class Heavy {
    public int $value = 0;
    public function __construct() {
        echo "constructed\n";
        $this->value = 42;
    }
}

$r = new ReflectionClass(Heavy::class);
$ghost = $r->newLazyGhost(function (Heavy $obj) {
    $obj->__construct();
});

echo "before access\n";
echo $ghost->value . "\n";
echo "after access\n";

// initializer fires once
echo $ghost->value . "\n";

// isUninitializedLazyObject before/after
$g2 = $r->newLazyGhost(function (Heavy $obj) { $obj->__construct(); });
var_dump($r->isUninitializedLazyObject($g2));
echo $g2->value . "\n";
var_dump($r->isUninitializedLazyObject($g2));

// initializeLazyObject: explicit trigger
$g3 = $r->newLazyGhost(function (Heavy $obj) { $obj->__construct(); });
$r->initializeLazyObject($g3);
echo "value=" . $g3->value . "\n";

// markLazyObjectAsInitialized: skip the initializer
$g4 = $r->newLazyGhost(function (Heavy $obj) {
    echo "should not run\n";
    $obj->__construct();
});
$r->markLazyObjectAsInitialized($g4);
echo "value=" . $g4->value . "\n";

// method call also triggers init
class Service {
    public string $name = "";
    public function __construct() {
        echo "service init\n";
        $this->name = "ready";
    }
    public function greet(): string { return "hello " . $this->name; }
}
$rs = new ReflectionClass(Service::class);
$svc = $rs->newLazyGhost(function (Service $s) { $s->__construct(); });
echo $svc->greet() . "\n";
