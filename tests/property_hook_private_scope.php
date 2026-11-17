<?php
// code in a class that declares a property private uses that declaration
// and its hooks, even on an object of a subclass that redeclares it, and a
// private hooked property is listed through its own class's hook

class A {
    private $plain = 'A plain';
    private $hooked {
        get { echo __METHOD__, "\n"; return 'A hooked'; }
        set { echo __METHOD__, "\n"; }
    }
    private $listed = 'listed in A' {
        get { return strtoupper($this->listed); }
    }

    public function fromA() {
        var_dump($this->plain);
        $this->plain = 'A wrote';
        var_dump($this->plain);
        var_dump($this->hooked);
        $this->hooked = 1;
    }

    public function exportFromA() {
        var_export($this);
        echo "\n";
    }
}

class B extends A {
    public $plain {
        get { echo __METHOD__, "\n"; return 'B plain'; }
        set { echo __METHOD__, "\n"; }
    }
    public $hooked {
        get { echo __METHOD__, "\n"; return 'B hooked'; }
        set { echo __METHOD__, "\n"; }
    }
    private $listed = 'listed in B' {
        get { return strtoupper($this->listed); }
    }
}

$b = new B();
$b->fromA();
echo "--\n";
var_dump($b->plain);
$b->plain = 1;
var_dump($b->hooked);
$b->hooked = 1;
echo "--\n";
var_export($b);
echo "\n";
$b->exportFromA();
echo json_encode($b), "\n";

// a child's get-only redeclaration of a backed property keeps the storage
class P {
    public function __construct(public $value) {}
}
class Q extends P {
    public $value {
        get { return "got {$this->value}"; }
    }
}
$q = new Q(5);
var_dump($q->value);
$q->value = 6;
var_dump($q->value);
