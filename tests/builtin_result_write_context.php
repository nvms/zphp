<?php
// strlen() compiles to an instruction whose result is a temporary
echo "never printed\n";
$x = strlen("foo")[0] ??= 1;
