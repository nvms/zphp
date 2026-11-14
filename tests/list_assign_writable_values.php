<?php
// a list() element must be something an assignment can write to: php
// refuses the script when it compiles it
function f() { return [1]; }
[$a, [$b], f()[0], $o->p[1]] = [1, [2], 3, 4];
[42] = [1];
