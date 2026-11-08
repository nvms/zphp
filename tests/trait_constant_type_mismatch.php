<?php
// a trait constant and the class's must have the same type
echo "not reached\n";
trait T { public const ?array LIST = []; }
class C { use T; public const array LIST = []; }
