<?php
// a by-reference foreach over an ArrayObject or ArrayIterator binds the loop
// variable to the storage's own elements, as spl_array's iterator does
$ao = new ArrayObject([1, 2, 3]);
foreach ($ao as $k => &$v) {
    $v *= 10;
}
unset($v);
var_dump($ao->getArrayCopy());

$it = new ArrayIterator(['a' => 'x', 'b' => 'y']);
foreach ($it as &$v) $v .= '!';
unset($v);
var_dump($it->getArrayCopy());

// nested loops over the same object share its elements
$obj = new ArrayObject([0, 1, 2]);
foreach ($obj as $ak => &$av) {
    foreach ($obj as $bk => &$bv) {
        if ($ak == 0 && $bk == 0) {
            $bv = "modify";
        }
        echo "$ak=>$av - $bk=>$bv\n";
    }
}
unset($av, $bv);

// a subclass with its own current() still can't be iterated by reference
class OwnCurrent extends ArrayIterator {
    function current(): mixed { return parent::current(); }
}
try {
    foreach (new OwnCurrent([1]) as &$v) {}
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
