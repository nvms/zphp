<?php
class DimensionBox {
    public private(set) array $items = [[1, 2]];
    public protected(set) int $number = 1;
    public private(set) object $inside;
    function __construct() { $this->inside = (object)['items' => [1, 2]]; }
    function legal() { $r =& $this->items[0][0]; $r = 7; unset($this->items[0][1]); changeNumber($this->number); }
}
class DimensionChild extends DimensionBox {
    function childLegal() { changeNumber($this->number); }
    function childDenied() { $r =& $this->items[0]; }
}
function changeNumber(&$n) { $n = 8; }
function checkDimension($fn) { try { $fn(); } catch (Error $e) { echo $e->getMessage(), "\n"; } }
$b = new DimensionBox;
checkDimension(function () use ($b) { $r =& $b->items[0]; });
checkDimension(function () use ($b) { $p = 'items'; $r =& $b->$p[0][0]; });
checkDimension(function () use ($b) { unset($b->items[0]); });
checkDimension(function () use ($b) { $p = 'items'; unset($b->$p[0][0]); });
checkDimension(function () use ($b) { changeNumber($b->number); });
checkDimension(function () use ($b) { $p = 'number'; changeNumber($b->$p); });
checkDimension(function () use ($b) { $p = 'items'; changeNumber($b->$p[0][0]); });
$count = 0;
function dimensionName() { global $count; $count++; return 'items'; }
checkDimension(function () use ($b) { $r =& $b->{dimensionName()}[0][0]; });
checkDimension(function () use ($b) { unset($b->{dimensionName()}[0][0]); });
echo "evaluations=$count\n";
$b->inside->items[0] = 3;
unset($b->inside->items[1]);
$child = new DimensionChild;
$child->childLegal();
checkDimension(function () use ($child) { $child->childDenied(); });
var_dump($child->number);
$b->legal();
var_dump($b->items, $b->number, $b->inside->items);
