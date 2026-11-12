<?php
$a = [[1]];
echo "never runs\n";
foreach ($a as list($this)) {
    var_dump($this);
}
