<?php
// an inherited property keeps being static, or not, and readonly, or not;
// a private one is not inherited and can change
class Base { public $counter = 0; private $secret; public static $shared; }
class Narrow extends Base { private static $secret; }
echo "private may change\n";
class Wrong extends Base { public static $counter = 1; }
echo "not reached\n";
