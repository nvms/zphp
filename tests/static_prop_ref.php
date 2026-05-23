<?php
// `$r = &Cls::$p` - ref to static property. zphp now emits a dedicated
// make_var_static_prop_ref opcode that creates a cell seeded from the static
// prop's current value, binds $r to it, and registers a writeback so writes
// through $r propagate to the class's static_props slot (walking the parent
// chain to find where the prop is actually declared). matches the existing
// obj-prop ref design - direct writes to the static prop don't update the
// already-bound cell (same as `$r = &$obj->p; $obj->p = X; echo $r;` not
// reflecting X), which is a pre-existing design limitation.
class C
{
    public static $count = 0;
    public static $list = [];
    public static $items = ['a'];
}

echo "== basic write through ref ==\n";
$r = &C::$count;
$r = 5;
echo "count via class: ", C::$count, "\n";
echo "count via ref: $r\n";

echo "== ref to array static prop ==\n";
$list = &C::$list;
$list[] = 'x';
$list[] = 'y';
echo "class count: ", count(C::$list), "\n";
echo "ref count: ", count($list), "\n";

echo "== ref to inherited static prop ==\n";
class D extends C {}
$r2 = &D::$count;
$r2 = 99;
echo "C count: ", C::$count, " D count: ", D::$count, "\n";

echo "== ref reads current value at bind time ==\n";
$items = &C::$items;
echo "items: ", implode(',', $items), "\n";
$items[] = 'b';
echo "after push, class: ", implode(',', C::$items), "\n";
