<?php
// parent::$prop::set() takes named and unpacked arguments, bound against
// the parent hook's parameter or the implicit hook's $value

class A {
    public mixed $plain;
    public mixed $custom {
        set(mixed $given) => $given * 10;
    }
    public mixed $read {
        get => 'parent get';
    }
}

class B extends A {
    public mixed $plain {
        set {
            parent::$plain::set(value: $value);
            try {
                parent::$plain::set(other: 1);
            } catch (Error $e) {
                echo get_class($e), ': ', $e->getMessage(), "\n";
            }
            try {
                parent::$plain::set(1, value: 2);
            } catch (Error $e) {
                echo get_class($e), ': ', $e->getMessage(), "\n";
            }
        }
    }
    public mixed $custom {
        set {
            parent::$custom::set(given: $value);
            try {
                parent::$custom::set(value: 1);
            } catch (Error $e) {
                echo get_class($e), ': ', $e->getMessage(), "\n";
            }
        }
    }
    public mixed $read {
        get {
            $args = [];
            return parent::$read::get(...$args) . ' via child';
        }
    }
}

$b = new B();
$b->plain = 5;
var_dump($b->plain);
$b->plain = [1, 2];
var_dump($b->plain);
$b->custom = 3;
var_dump($b->custom);
var_dump($b->read);

class C extends A {
    public mixed $plain {
        set {
            $args = [$value];
            parent::$plain::set(...$args);
        }
    }
}
$c = new C();
$c->plain = 'unpacked';
var_dump($c->plain);
