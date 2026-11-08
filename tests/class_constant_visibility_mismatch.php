<?php
// a constant can't narrow the visibility of the one it overrides
echo "not reached\n";
class Base { protected const LIMIT = 1; }
class Child extends Base { private const LIMIT = 2; }
