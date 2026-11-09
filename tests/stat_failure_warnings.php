<?php
// the stat family warns when a path cannot be stat'ed, and takes any scalar
$missing = "/zphp_no_such_dir/missing";
foreach (['fileinode', 'fileperms', 'filesize', 'filemtime', 'fileatime', 'filectime', 'filetype', 'stat', 'lstat'] as $fn) {
    var_dump($fn($missing));
    var_dump($fn(100));
    var_dump($fn(""));
}
var_dump(is_link($missing), is_file(""), file_exists(""));

$file = sys_get_temp_dir() . "/zphp_stat_file_" . getmypid();
file_put_contents($file, "abc");
var_dump(filetype($file), filesize($file), fileinode($file) === stat($file)['ino']);
$st = lstat($file);
var_dump(count($st), $st['size'], $st[7], $st['nlink']);
$f = fopen($file, "r");
$fst = fstat($f);
var_dump(count($fst), $fst['size'], $fst['ino'] === $st['ino'], $fst['mode'] === $st['mode']);
fclose($f);
var_dump(filetype(sys_get_temp_dir()));
unlink($file);
