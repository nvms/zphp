<?php
echo "not reached\n";
class P { public $a; public $b; } class C extends P { public $a { get => parent::$b::get(); } }
