<?php
// php's method compatibility checks when a class is declared: tentative
// return types of internal interfaces warn, #[\ReturnTypeWillChange] (on the
// method, a trait method, or an abstract method) silences that, and a
// signature that does fit passes quietly
error_reporting(E_ALL);
set_error_handler(function ($no, $msg, $file, $line) {
    echo "[$no] $msg (line $line)\n";
    return true;
});

if (true) {
    class Loose implements ArrayAccess, Countable, IteratorAggregate {
        function offsetGet($o) {}
        function offsetSet($o, $v): void {}
        function offsetExists($o): bool { return false; }
        function offsetUnset($o): void {}
        function count() { return 0; }
        function getIterator(): Iterator { return new ArrayIterator([]); }
    }

    trait Quiet {
        #[ReturnTypeWillChange]
        public function current() { return null; }
    }
    abstract class Listing implements Iterator {
        use Quiet;
        #[ReturnTypeWillChange]
        abstract public function key();
        public function next(): void {}
        public function valid(): bool { return false; }
        public function rewind(): void {}
    }
    class Concrete extends Listing {
        #[ReturnTypeWillChange]
        public function key() { return 0; }
    }

    abstract class Shape { abstract public static function make(): static; }
    final class Square extends Shape { public static function make(): static { return new static; } }

    class Text implements Stringable { public function __toString() { return 'text'; } }

    interface Source { public function read(array $into = [], string $mode = 'binary-mode', ...$rest); }
    class File implements Source { public function read(array $into = [], string $mode = 'r', ...$more) {} }

    class Seeker extends ArrayIterator { public function seek(int $offset): void {} }
}

var_dump((string) (new ReflectionMethod('Text', '__toString'))->getReturnType());
var_dump(class_implements('Seeker') == class_implements('ArrayIterator'));
var_dump(in_array('SeekableIterator', class_implements('ArrayIterator')), in_array('OuterIterator', class_implements('IteratorIterator')));
foreach (['SeekableIterator', 'OuterIterator', 'SplObserver', 'SplSubject'] as $name) {
    var_dump(interface_exists($name), (new ReflectionClass($name))->isInternal());
}
echo "done\n";
