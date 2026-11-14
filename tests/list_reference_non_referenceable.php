<?php
// destructuring by reference needs a variable or a call on the right: php
// refuses the script when it compiles it
$source = [1];
[&$a] = $source;
list(&$foo) = [42];
