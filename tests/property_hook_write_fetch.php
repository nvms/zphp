<?php
// write fetches of hooked properties (by-reference arguments, `$r = &$o->p`,
// `$o->p[] = v`) follow php's read_property(BP_VAR_W): a &get hook hands
// over its reference, a by-value result or a set-only hook's backing value
// must be an object

class RefGet {
    private $store = 1;
    public $prop {
        &get => $this->store;
        set { $this->store = $value; }
    }
}

class SetOnly {
    public $p {
        set { echo "set ", json_encode($value), "\n"; $this->p = $value; }
    }
}

class ByVal {
    public $p {
        get => [1];
    }
    public $o {
        get => new ArrayObject([]);
    }
}

function inc(&$ref) {
    $ref++;
}
function push(&$ref) {
    $ref[] = 'x';
}

$r = new RefGet();
inc($r->prop);
inc($r->prop);
var_dump($r);
var_dump($r->prop);

$s = new SetOnly();
$s->p = [];
foreach ([
    'append' => function () use ($s) { $s->p[] = 1; },
    'ref' => function () use ($s) { $x = &$s->p; },
    'arg' => function () use ($s) { push($s->p); },
] as $what => $f) {
    try {
        $f();
        echo "$what: no error\n";
    } catch (Error $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}
var_dump($s->p);

$s2 = new SetOnly();
$s2->p = new ArrayObject([]);
push($s2->p);
var_dump(count($s2->p));

$b = new ByVal();
try {
    push($b->p);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
push($b->o);
echo "object fetch ok\n";
