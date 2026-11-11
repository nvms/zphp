<?php
// count() turns what a Countable's count() returns into an int as
// zval_get_long does: an object that can't be converted warns and counts 1
class Returns implements Countable {
    function __construct(private $v) {}
    #[ReturnTypeWillChange]
    function count() { return $this->v; }
}
foreach ([3, '7 apples', 2.9, null, true, [1, 2], new stdClass, new ArrayObject([1])] as $v) {
    var_dump(@count(new Returns($v)));
}
var_dump(count(new Returns(new stdClass)));
