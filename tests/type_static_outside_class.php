<?php
// static as a type needs a class scope; a closure's is only known once bound
$f = function (): static { return $this; };
echo "not reached\n";
function make(): static {}
