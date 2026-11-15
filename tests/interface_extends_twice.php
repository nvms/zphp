<?php
// an interface may name each parent once, aliases included
interface a {}
class_alias("a", "b");
interface c extends a, b {}
echo "not reached\n";
