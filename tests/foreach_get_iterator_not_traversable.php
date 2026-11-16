<?php
// foreach over an IteratorAggregate whose getIterator() returns something
// other than a Traversable throws, as php's zend_user_it_get_new_iterator does

class ReturnsArray implements IteratorAggregate {
    #[ReturnTypeWillChange]
    public function getIterator() { return ['a', 'b']; }
}
class ReturnsSelf implements IteratorAggregate {
    #[ReturnTypeWillChange]
    public function getIterator() { return $this; }
}
class ReturnsNull implements IteratorAggregate {
    #[ReturnTypeWillChange]
    public function getIterator() { return null; }
}
class ReturnsAggregate implements IteratorAggregate {
    public function getIterator(): Traversable { return new ReturnsArray; }
}
class ReturnsGenerator implements IteratorAggregate {
    public function getIterator(): Traversable { yield 1; yield 2; }
}

foreach ([new ReturnsArray, new ReturnsSelf, new ReturnsNull, new ReturnsAggregate, new ReturnsGenerator] as $obj) {
    try {
        foreach ($obj as $k => $v) {
            echo "$k => $v\n";
        }
        echo "done\n";
    } catch (Exception $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
