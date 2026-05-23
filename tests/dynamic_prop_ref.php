<?php
// `$r = &$obj->$name` - ref to a dynamic property. compiler now detects the
// dynamic-prop shape on `=&` and emits make_var_prop_ref_dyn (pops object
// AND prop_name_string from the stack), routing through the same
// ref_object_bindings writeback as the static-name case.
class C
{
    public $x = 0;
    public $y = 10;
    public $z = 'init';
}

$o = new C;

$name = 'x';
$r = &$o->$name;
$r = 99;
echo "x=", $o->x, " y=", $o->y, "\n";

$name = 'y';
$r2 = &$o->$name;
$r2 = 42;
echo "y=", $o->y, "\n";

$r2 = 7;
echo "y after rebind: ", $o->y, "\n";

$name = 'z';
$rz = &$o->$name;
$rz = 'reassigned';
echo "z=", $o->z, "\n";

// loop over multiple props by name
foreach (['x', 'y', 'z'] as $k) {
    $cell = &$o->$k;
    $cell = "set-$k";
    unset($cell);
}
echo "after loop: x=", $o->x, " y=", $o->y, " z=", $o->z, "\n";
