<?php
echo "start\n";
trait T1 { function f() {} } trait T2 { function f() {} } class C { use T1 { T2::f insteadof T1; } }
