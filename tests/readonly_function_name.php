<?php
// readonly followed by ( is a name, so a function can be called readonly
function readonly() { return 'readonly called'; }
echo readonly(), ' ', readonly (), "\n";
final readonly class Point { public function __construct(public int $x) {} }
echo (new Point(1))->x, "\n";
