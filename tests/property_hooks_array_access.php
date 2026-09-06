<?php
// Reduced from php-src Zend/tests/property_hooks/array_access.phpt.

class Collection implements ArrayAccess {
    public function offsetExists(mixed $offset): bool {
        echo __METHOD__ . "\n";
        return true;
    }

    public function offsetGet(mixed $offset): mixed {
        echo __METHOD__ . "\n";
        return true;
    }

    public function offsetSet(mixed $offset, mixed $value): void {
        echo __METHOD__ . "\n";
    }

    public function offsetUnset(mixed $offset): void {
        echo __METHOD__ . "\n";
    }
}

class C {
    public function __construct(
        public Collection $collection = new Collection(),
    ) {}
    public $prop {
        get => $this->collection;
    }
}

$c = new C();
var_dump($c->prop['foo']);
var_dump($c->prop[] = 'foo');
var_dump(isset($c->prop['foo']));
unset($c->prop['foo']);

// Indexed assignment uses prop_set_chain instead of ensure_array_prop.
var_dump($c->prop['key'] = 'bar');
// Hook exceptions must reach the surrounding PHP handler.
class FailingCollection {
    public $prop { get { throw new Exception('getter failed'); } }
}
$f = new FailingCollection;
try { $f->prop[] = 1; }
catch (Exception $e) { echo $e->getMessage(), "\n"; }
try { $f->prop['key'] = 1; }
catch (Exception $e) { echo $e->getMessage(), "\n"; }
