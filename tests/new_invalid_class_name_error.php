<?php
// `new` on a value that names no class is an Error a catch can take
foreach ([null, 42, 1.5, true, [1]] as $class) {
    try {
        var_dump(new $class);
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        var_dump(new $class(1, 2));
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
echo "done\n";
