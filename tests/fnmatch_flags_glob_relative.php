<?php
// fnmatch follows the platform's fnmatch(3) and its flag values, and a
// glob pattern without a directory names what it finds bare
var_dump(FNM_NOESCAPE, FNM_PATHNAME, FNM_PERIOD, FNM_CASEFOLD);
$cases = [
    ["*.txt", "dir/file.txt", 0],
    ["*.txt", "dir/file.txt", FNM_PATHNAME],
    ["*/file.txt", "dir/file.txt", FNM_PATHNAME],
    ["*", ".hidden", 0],
    ["*", ".hidden", FNM_PERIOD],
    ["\\*", "*", 0],
    ["\\*", "\\*", FNM_NOESCAPE],
    ["[a-c]x", "bx", 0],
    ["[!a-c]x", "bx", 0],
    ["A*", "abc", FNM_CASEFOLD],
    ["a?c", "a/c", FNM_PATHNAME],
];
foreach ($cases as [$pattern, $name, $flags]) {
    var_dump(fnmatch($pattern, $name, $flags));
}
var_dump(fnmatch("*", str_repeat("x", 5000)), fnmatch(str_repeat("x", 5000), "x"));
foreach (["a\0b", "x"] as $i => $p) {
    try {
        $i ? fnmatch("x", "a\0") : fnmatch($p, "x");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}

$base = sys_get_temp_dir() . "/zphp_glob_" . getmypid();
mkdir($base);
touch("$base/one.txt");
mkdir("$base/sub");
chdir($base);
var_dump(glob("*"), glob("sub"), glob("*.txt", GLOB_MARK), glob("./*.txt"));
try {
    glob("a\0");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
chdir("/");
unlink("$base/one.txt");
rmdir("$base/sub");
rmdir($base);
