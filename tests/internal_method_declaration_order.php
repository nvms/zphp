<?php
// a built-in class lists its methods in the order php's stubs declare them,
// its own first, then the ones it inherits

foreach (['DateTime', 'DatePeriod', 'SplDoublyLinkedList', 'SplQueue', 'SplFixedArray', 'SplObjectStorage', 'SplFileObject', 'DirectoryIterator', 'RecursiveIteratorIterator', 'CachingIterator', 'PhpToken', 'ReflectionEnum', 'WeakReference'] as $class) {
    echo $class, ":\n";
    foreach ((new ReflectionClass($class))->getMethods() as $m) {
        echo "  ", $m->class, "::", $m->name, "\n";
    }
    echo "  ", implode(' ', get_class_methods($class)), "\n";
}
