<?php
// realpath() resolves through php's realpath cache: an answer stays until
// its entry expires or clearstatcache(true), unlink, rename or rmdir drops
// it, and realpath_cache_get() lists the entries
$base = sys_get_temp_dir() . '/zrp' . getmypid();
@mkdir($base);
$base = realpath($base);
$show = fn($v) => is_string($v) ? str_replace($base, 'BASE', $v) : $v;

mkdir("$base/dir1");
symlink("$base/link1", "$base/link2");
symlink("$base/dir1", "$base/link1");
var_dump($show(realpath("$base/link2")));
// removed behind php's back: the cache still answers
exec('rm -f ' . escapeshellarg("$base/link1"));
var_dump($show(realpath("$base/link2")));
clearstatcache();
var_dump($show(realpath("$base/link2")));
clearstatcache(true, "/no/such/path");
var_dump($show(realpath("$base/link2")));
clearstatcache(true, "");
var_dump($show(realpath("$base/link2")));
clearstatcache(true, "$base/link2");
var_dump($show(realpath("$base/link2")));
clearstatcache(true, "$base/link1");
var_dump($show(realpath("$base/link2")));

symlink("$base/dir1", "$base/link1");
var_dump($show(realpath("$base/link2/../dir1/./")));
exec('rm -f ' . escapeshellarg("$base/link1"));
clearstatcache(true);
var_dump($show(realpath("$base/link2")));

// unlink drops the whole cache
touch("$base/f");
var_dump($show(realpath("$base/f")));
exec('rm -f ' . escapeshellarg("$base/f"));
var_dump($show(realpath("$base/f")));
@unlink("$base/none");
var_dump($show(realpath("$base/f")));

$entries = realpath_cache_get();
$mine = array_filter($entries, fn($k) => str_starts_with($k, $base), ARRAY_FILTER_USE_KEY);
ksort($mine);
foreach ($mine as $path => $entry) {
    echo $show($path), ': ', $show($entry['realpath']), ' ', var_export($entry['is_dir'], true), ' ',
        is_int($entry['key']) || is_float($entry['key']) ? 'key' : 'nokey', ' ',
        $entry['expires'] - time() > 100 ? 'ttl' : 'expired', "\n";
}
var_dump(realpath_cache_size() > 0);
unlink("$base/link2");
var_dump(count(array_filter(array_keys(realpath_cache_get()), fn($k) => str_starts_with($k, $base))));

// so does a rename
touch("$base/g");
var_dump($show(realpath("$base/g")));
exec('rm -f ' . escapeshellarg("$base/g"));
touch("$base/h");
rename("$base/h", "$base/i");
var_dump(realpath("$base/g"));
unlink("$base/i");

// relative paths, and a working directory that was removed
chdir("$base/dir1");
var_dump($show(realpath('')), $show(realpath('.')), $show(realpath('..')), realpath('nope'));
mkdir("$base/gone");
chdir("$base/gone");
rmdir("$base/gone");
var_dump(getcwd(), realpath(''), realpath('.'), realpath('./'), realpath('x/..'));
chdir(sys_get_temp_dir());
rmdir("$base/dir1");
rmdir($base);
