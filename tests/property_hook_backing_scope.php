<?php
// inside a property's hook only the object the hook runs on reaches the
// backing value; the same property of another object runs its hook

class C {
    public $switch;

    public $prop = 42 {
        get {
            echo __METHOD__, "\n";
            if ($this->switch) {
                $other = new C();
                $other->switch = false;
            } else {
                $other = $this;
            }
            var_dump($other->prop);
            return 1;
        }
        set => $this->prop;
    }
}

function test() {
    $c = new C();
    $c->switch = true;
    var_dump($c->prop);
}

test();
test();

class Node {
    public ?Node $next = null;
    public int $value = 0 {
        set {
            echo "set {$value}\n";
            $this->value = $value;
            if ($this->next) $this->next->value = $value + 1;
        }
    }
}

function link_nodes() {
    $a = new Node;
    $a->next = new Node;
    $a->value = 1;
    $a->value = 5;
    var_dump($a->value, $a->next->value);
}
link_nodes();
link_nodes();

// a get-only hook that uses its backing value keeps the implicit set
class Backed {
    public $prop {
        get {
            echo __METHOD__, "\n";
            return $this->prop;
        }
    }
}
$b = new Backed();
$b->prop = 42;
var_dump($b->prop);

class Virtual {
    public $prop {
        get => 7;
    }
}
try {
    $v = new Virtual();
    $v->prop = 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

// a trait's hooks name the trait in their magic constants
trait T {
    public $tp {
        get { echo __METHOD__, " ", __CLASS__, " ", __FUNCTION__, " ", __TRAIT__, "\n"; return 1; }
        set { echo __METHOD__, " ", __CLASS__, "\n"; }
    }
}
class UsesT { use T; }
$u = new UsesT;
$u->tp;
$u->tp = 2;
