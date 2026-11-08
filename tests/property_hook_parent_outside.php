<?php
echo "not reached\n";
class A { function f() { return parent::$x::get(); } }
