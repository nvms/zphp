<?php
// a property fetched to write, read-write or unset through it: a readonly or
// private(set) property only lets an object in it be written through, an
// uninitialized one is refused for a write, reported uninitialized for a
// read-write and reads as nothing for an unset
class Inner {
    public int $prop = 1;
    public array $array = [];
}

class Test {
    public readonly Inner $ro;
    public private(set) Inner $ps;
    public private(set) array $arr;
    public readonly int $scalar;

    public function init() {
        $this->ro = new Inner();
        $this->ps = new Inner();
        $this->arr = [1];
        $this->scalar = 5;
    }
}

foreach ([true, false] as $init) {
    foreach (['ro', 'ps'] as $p) {
        foreach (['w', 'rw', 'im', 'is', 'us', 'us_dim'] as $name) {
            $t = new Test();
            if ($init) $t->init();
            echo (int) $init, " $p $name: ";
            try {
                match ($p . $name) {
                    'row' => $t->ro->prop = 0,
                    'rorw' => $t->ro->prop += 1,
                    'roim' => $t->ro->array[] = 1,
                    'rois' => print((int) isset($t->ro->prop) . " "),
                    'rous' => (function () use ($t) { unset($t->ro->prop); })(),
                    'rous_dim' => (function () use ($t) { unset($t->ro->array[0]); })(),
                    'psw' => $t->ps->prop = 0,
                    'psrw' => $t->ps->prop += 1,
                    'psim' => $t->ps->array[] = 1,
                    'psis' => print((int) isset($t->ps->prop) . " "),
                    'psus' => (function () use ($t) { unset($t->ps->prop); })(),
                    'psus_dim' => (function () use ($t) { unset($t->ps->array[0]); })(),
                };
                echo "done";
            } catch (Error $e) {
                echo $e->getMessage();
            }
            echo "\n";
        }
    }
}

$t = new Test();
foreach (['unset($t->arr[0]);', '$t->arr[] = 2;'] as $code) {
    try {
        eval($code);
        echo "done\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
$t->init();
foreach (['unset($t->arr[0]);', '$t->arr[] = 2;', '$t->scalar++;'] as $code) {
    try {
        eval($code);
        echo "done\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
