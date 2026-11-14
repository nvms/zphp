<?php
// a by-reference foreach over a call's result writes into the result, not
// into the variable the result was copied from, unless the call returned
// a reference

function id($x) { return $x; }
function &ref_id(&$x) { return $x; }

class Box
{
    public array $items = ['p', 'q'];
    public function items(): array { return $this->items; }
    public function &itemsRef(): array { return $this->items; }
}

$array = ['a', 'b'];
foreach (id($array) as &$v) { $v .= '1'; }
unset($v);
echo implode(",", $array), "\n";

foreach (ref_id($array) as &$v) { $v .= '2'; }
unset($v);
echo implode(",", $array), "\n";

$c = 'c';
$array = ['a', 'b', $c];
foreach (id($array) as $k => &$v) { $v .= "-$k"; }
var_dump($array);
unset($v);

$box = new Box;
foreach ($box->items() as &$v) { $v = strtoupper($v); }
unset($v);
echo implode(",", $box->items), "\n";
foreach ($box->itemsRef() as &$v) { $v = strtoupper($v); }
unset($v);
echo implode(",", $box->items), "\n";

// the copy the loop wrote to is its own
$seen = [];
foreach (array_values($array) as &$v) { $v = 'x'; $seen[] = $v; }
unset($v);
echo implode(",", $array), " / ", implode(",", $seen), "\n";

$nested = [[1, 2], [3]];
foreach (id($nested) as &$row) { $row[] = 0; }
unset($row);
echo json_encode($nested), "\n";
