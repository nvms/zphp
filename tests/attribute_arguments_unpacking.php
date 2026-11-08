<?php
echo "not reached\n";
#[Attribute]
class A { function __construct(...$a) {} }
#[A(...[1, 2])]
class B {}
