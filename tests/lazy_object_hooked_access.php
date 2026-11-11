<?php
// a hooked property of a lazy object runs its hook first: the object is
// initialized only when the hook reaches the object's own state

class C {
    public int $b = 1;
    public int $virtual {
        get { return 42; }
        set { echo "set virtual\n"; }
    }
    public int $reads {
        get { return $this->b; }
    }
    public function __construct() { var_dump(__METHOD__); }
}
$r = new ReflectionClass(C::class);
$obj = $r->newLazyGhost(function ($o) { var_dump("initializer"); $o->__construct(); });
var_dump($obj->virtual);
var_dump(isset($obj->virtual));
$obj->virtual = 3;
try { unset($obj->virtual); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($r->isUninitializedLazyObject($obj));
var_dump($obj->reads);
var_dump($r->isUninitializedLazyObject($obj));

// a backed property with only a set hook is read from storage, which
// initializes the object
class SetOnly {
    public string $bar {
        set => $value;
    }
}
$r2 = new ReflectionClass(SetOnly::class);
$foo = $r2->newLazyGhost(function ($ghost) { $ghost->bar = 'bar'; });
echo $foo->bar, "\n";
