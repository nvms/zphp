<?php
// debug_zval_dump prints an enum case as the object it is, with its count
enum Foo {
    case Bar;
}
enum Num: int {
    case One = 1;
}
debug_zval_dump(Foo::Bar);
$foo = Foo::Bar;
debug_zval_dump($foo);
$bar = unserialize('E:7:"Foo:Bar";');
debug_zval_dump($foo);
unset($bar);
debug_zval_dump($foo);
debug_zval_dump(Num::One);
