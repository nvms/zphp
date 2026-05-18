<?php
// regression: glob with GLOB_NOCHECK returns the literal pattern as a
// single-element array when no entries matched. previously zphp returned
// an empty array regardless of the flag. also adds the dir() function
// returning a Directory object with path/handle properties + read/rewind/
// close methods (delegating to readdir/rewinddir/closedir)
$tmp = "/tmp/zphp_dir_glob_test";
@mkdir($tmp);
file_put_contents("$tmp/a.txt", "1");
file_put_contents("$tmp/b.txt", "2");

// GLOB_NOCHECK pattern preserved
print_r(glob("$tmp/no_match_*", GLOB_NOCHECK));
print_r(glob("$tmp/no_match_*"));   // empty array without the flag

// dir() returns Directory
$d = dir($tmp);
echo "path: " . $d->path . "\n";
echo "is Directory: " . ($d instanceof Directory ? 'y' : 'n') . "\n";

$names = [];
while (($n = $d->read()) !== false) $names[] = $n;
sort($names);
foreach ($names as $n) echo "read: $n\n";

$d->rewind();
echo "after rewind: " . $d->read() . "\n";   // first entry again

$d->close();

unlink("$tmp/a.txt");
unlink("$tmp/b.txt");
rmdir($tmp);
