<?php
// ArrayIterator has ArrayObject's flag constants, and a built-in class lists
// the constants it inherits before its own; a user class lists its own first
class Foo extends RecursiveArrayIterator {
    const MINE = 8;
}
var_dump(ArrayIterator::ARRAY_AS_PROPS, RecursiveArrayIterator::STD_PROP_LIST);
foreach (['ArrayIterator', 'RecursiveArrayIterator', 'Foo', 'RecursiveCachingIterator', 'RecursiveRegexIterator',
    'RecursiveTreeIterator', 'SplQueue', 'GlobIterator', 'SplTempFileObject', 'MultipleIterator'] as $class) {
    echo $class, ': ', json_encode((new ReflectionClass($class))->getConstants()), "\n";
}
