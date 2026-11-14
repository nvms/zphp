<?php
// php's grammar has no dereference of `new C` without an argument list

class A {
    public $prop = 'property';
}

echo "unreachable\n";
echo new A->prop;
