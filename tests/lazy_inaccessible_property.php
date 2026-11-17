<?php
// a property the caller can't see fails or goes to __get without
// initializing a lazy object

class Secret {
    private $priv = 'p';
    protected $prot = 'q';
    public $pub = 'r';
}

class Magic {
    private $hidden = 'h';
    public $shown = 's';
    public function __get($n) { echo "__get($n)\n"; return 'magic'; }
}

$rs = new ReflectionClass(Secret::class);
foreach (['Ghost', 'Proxy'] as $kind) {
    $make = $kind === 'Ghost'
        ? fn () => $rs->newLazyGhost(function ($o) { echo "init\n"; })
        : fn () => $rs->newLazyProxy(function ($o) { echo "init\n"; return new Secret(); });
    foreach (['priv', 'prot', 'pub'] as $name) {
        $o = $make();
        try {
            var_dump($o->$name);
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
        var_dump($rs->isUninitializedLazyObject($o));
    }
}

$rm = new ReflectionClass(Magic::class);
$o = $rm->newLazyGhost(function ($o) { echo "init magic\n"; });
var_dump($o->hidden);
var_dump($rm->isUninitializedLazyObject($o));
var_dump($o->shown);
var_dump($rm->isUninitializedLazyObject($o));
