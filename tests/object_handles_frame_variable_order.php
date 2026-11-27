<?php
// a returning function frees its variables one at a time, in order: what an
// earlier variable's object held is released before the next variable goes,
// so handles return to the free list in php's order

class Bar {}

class Foo
{
    public private(set) Bar $bar;

    public function __construct()
    {
        $this->bar = new Bar();
    }
}

function plain()
{
    $holder = new stdClass();
    $holder->child = new Bar();
    $alias = $holder->child;
}

function reference()
{
    $foo = new Foo();
    $bar = &$foo->bar;
}

function withDestructor()
{
    $a = new class {
        public $child;
        public function __destruct()
        {
            echo "destruct a\n";
        }
    };
    $a->child = new class {
        public function __destruct()
        {
            echo "destruct child\n";
        }
    };
    $b = $a->child;
    $c = new class {
        public function __destruct()
        {
            echo "destruct c\n";
        }
    };
}

plain();
var_dump(new stdClass(), new Bar());

reference();
var_dump(new Foo());
reference();
var_dump(new Foo());

withDestructor();
echo "after\n";
var_dump(new stdClass());
