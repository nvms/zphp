<?php
// a virtual property has no storage: var_dump, (array) and serialize leave
// it out, while get_object_vars, var_export, json_encode and foreach read
// hooked properties through their get hooks, in declaration order

#[AllowDynamicProperties]
class Test {
    public $addedHooks = 'addedHooks';
    public $virtual {
        get { return strtoupper('virtual'); }
    }
    public $backed = 'backed' {
        get { return strtoupper($this->backed); }
        set { $this->backed = $value; }
    }
    public $writeOnly {
        set {}
    }
    private $private = 'private' {
        get { return strtoupper($this->private); }
    }
    public function inside() {
        var_dump(get_object_vars($this));
        foreach ($this as $k => $v) echo "$k => $v\n";
    }
}
$t = new Test;
$t->dynamic = 'dynamic';
var_dump($t);
var_dump(get_object_vars($t));
var_export($t);
echo "\n", json_encode($t), "\n";
var_dump((array) $t);
echo serialize($t), "\n";
foreach ($t as $k => $v) echo "$k => $v\n";
$t->inside();
var_dump(get_class_vars('Test'));

class Child extends Test {
    public $addedHooks = 'addedHooks' {
        get { return 'child ' . $this->addedHooks; }
    }
}
echo json_encode(new Child), "\n";
