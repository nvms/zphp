<?php
// regression: declaring a class with a reserved type-keyword name is a fatal
// error ("Cannot use ... as a class name as it is reserved"), matching PHP.
// zphp previously accepted such declarations silently. the declaration below
// must abort with the identical fatal in both runtimes.
class Mixed {}
echo "unreachable\n";
