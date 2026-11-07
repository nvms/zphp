<?php
// a nested list is written the way the outer one is
[$a, list($b)] = [1, [2]];
var_dump($a, $b);
