<?php
// glob() negates a bracket expression that starts with "!" or "^", and the
// expression's first character is taken as itself, even "]"
$dir = sys_get_temp_dir() . '/zphp_glob_neg_' . getmypid();
@mkdir($dir);
$names = ['a', 'b', 'c', '^', '!', ']', 'ab', 'ba'];
foreach ($names as $name) {
    touch("$dir/$name");
}

foreach (['[!a]', '[^a]', '[!a-b]', '[^a-b]', '[!]a]', '[^]a]', '[]a]', '[a^]', '[!^]', '[^^]', '[^!]', '[!!]', '[^a]*', '*[^a]', '[]', '[!]', '[^]'] as $pattern) {
    $found = array_map('basename', glob("$dir/$pattern"));
    sort($found);
    echo str_pad($pattern, 8), ': ', implode(' ', $found), "\n";
}

foreach ($names as $name) {
    unlink("$dir/$name");
}
rmdir($dir);
