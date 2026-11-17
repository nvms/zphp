<?php
// a class whose properties are all virtual has no storage for them

class OnlyVirtual {
    public $a {
        get => 42;
    }
    public $b {
        get => 'b';
        set { echo "set b\n"; }
    }
}

$o = new OnlyVirtual();
var_dump($o);
print_r($o);
echo "\n";
var_dump((array) $o);
var_dump(get_object_vars($o));
echo json_encode($o), "\n";

#[AllowDynamicProperties]
class WithDynamic {
    public $a {
        get => 42;
    }
}
$w = new WithDynamic();
$r = &$w->dyn;
unset($r);
echo json_encode($w), "\n";
var_dump($w);
