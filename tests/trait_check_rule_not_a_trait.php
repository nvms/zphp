<?php
echo "start\n";
class P { function m() {} } trait T { function m() {} } class C { use T { P::m insteadof T; } }
