<?php
// the methods of php's own interfaces, in php's order, with the ones they
// inherit from the interfaces they extend

foreach (['ArrayAccess', 'BackedEnum', 'UnitEnum', 'Countable', 'Iterator', 'IteratorAggregate', 'OuterIterator', 'RecursiveIterator', 'SeekableIterator', 'SplObserver', 'SplSubject', 'Stringable', 'Throwable', 'Traversable', 'JsonSerializable', 'DateTimeInterface', 'Serializable'] as $iface) {
    echo $iface, ': ', implode(', ', get_class_methods($iface)), "\n";
}

class Partial implements Iterator {
    public function current(): mixed { return null; }
}
