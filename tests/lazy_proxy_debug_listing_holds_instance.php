<?php
// an initialized proxy's debug view holds its instance while it is listed,
// and lets it go afterwards

class C {
    public $a = 1;
    public function __destruct() { echo "destruct ", spl_object_id($this) === $GLOBALS['id'] ? "instance" : "other", "\n"; }
}

$r = new ReflectionClass(C::class);
$proxy = $r->newLazyProxy(function () { return new C(); });
$instance = $r->initializeLazyObject($proxy);
$GLOBALS['id'] = spl_object_id($instance);
unset($instance);

debug_zval_dump($proxy);
var_dump($proxy);
print_r($proxy);
echo "\n";
echo "dropping proxy\n";
$proxy = null;
echo "done\n";
