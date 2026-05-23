<?php
// Stage 2 element-overwrite release: set_static_prop now drops the previous
// value's retain so the displaced object can __destruct at the overwrite
// point. set_prop (instance) already did this since Stage 1; this commit
// extends to the static-prop opcode.
class T
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

class Holder
{
    public static $sfield;
}

echo "== static prop overwrite ==\n";
Holder::$sfield = new T('A');
echo "before overwrite\n";
Holder::$sfield = new T('B');
echo "after overwrite\n";
Holder::$sfield = 0;
echo "after scalar overwrite\n";

echo "== chained overwrites ==\n";
Holder::$sfield = new T('C');
Holder::$sfield = new T('D');
Holder::$sfield = new T('E');
echo "after chain\n";
Holder::$sfield = null;
echo "done\n";
