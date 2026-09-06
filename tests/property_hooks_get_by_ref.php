<?php
// Reduced from php-src Zend/tests/property_hooks/get_by_ref.phpt.

class Test {
    public $byVal {
        get { return $this->byVal; }
        set { $this->byVal = $value; }
    }
}

$test = new Test;

try {
    $test->byVal = [];
    $test->byVal[] = 42;
} catch (\Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump($test->byVal);

try {
    $test->byVal =& $ref;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

// Indexed writes use a separate VM path from append.
try { $test->byVal['key'] = 7; }
catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($test->byVal);
// Dynamic reference destinations must reject the binding too.
$name = 'byVal';
try { $test->$name =& $ref; }
catch (Error $e) { echo $e->getMessage(), "\n"; }
// Recursion guard still permits the hook to modify its backing array.
class BackedArray {
    public array $items = [] {
        get { return $this->items; }
        set { $this->items[] = $value[0]; }
    }
}
$b = new BackedArray;
$b->items = [9];
var_dump($b->items);
try { $alias =& $test->byVal; }
catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $alias =& $test->$name; }
catch (Error $e) { echo $e->getMessage(), "\n"; }
