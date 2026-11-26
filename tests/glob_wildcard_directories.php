<?php
// wildcards in a pattern's directory components match directories
$base = sys_get_temp_dir() . '/zphp_glob_dirs_' . getmypid();
foreach (['a/b/sub', 'a/c/d', 'a/.hidden', 'e', 'br[ack/in'] as $d) mkdir("$base/$d", 0777, true);
foreach (['a/b/sub/x.txt', 'a/b/sub/y.txt', 'a/b/z.txt', 'a/c/d/q', 'a/.hidden/h', 'e/f.txt', 'file'] as $f) touch("$base/$f");

$show = function ($r) use ($base) {
    if (!is_array($r)) return var_export($r, true);
    return '[' . implode(', ', array_map(fn($p) => str_replace($base, 'BASE', $p), $r)) . ']';
};
foreach ([
    ["$base/*/*/*", 0],
    ["$base/*/*", 0],
    ["$base/*/*/", GLOB_MARK],
    ["$base/*/*", GLOB_MARK],
    ["$base/*/*", GLOB_ONLYDIR],
    ["$base/a/[bc]/*", 0],
    ["$base/?/*.txt", 0],
    ["$base/a/.*/*", 0],
    ["$base/*/nothing/*", 0],
    ["$base/{a,e}/*", GLOB_BRACE],
    ["$base/*/in", 0],
    ["$base/*/in/", 0],
    ["$base/b*/*", GLOB_MARK],
] as [$pattern, $flags]) {
    echo str_replace($base, 'BASE', $pattern), ' ', $flags, ': ', $show(glob($pattern, $flags)), "\n";
}

foreach (new GlobIterator("$base/*/*/*.txt") as $info) echo $info->getFilename(), "\n";
var_dump(count(new GlobIterator("$base/*/*/*")));

foreach (array_reverse(['a/b/sub/x.txt', 'a/b/sub/y.txt', 'a/b/z.txt', 'a/c/d/q', 'a/.hidden/h', 'e/f.txt', 'file']) as $f) unlink("$base/$f");
foreach (['a/b/sub', 'a/b', 'a/c/d', 'a/c', 'a/.hidden', 'a', 'e', 'br[ack/in', 'br[ack', ''] as $d) rmdir("$base/$d");
var_dump(file_exists($base));
