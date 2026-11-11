<?php
// only a declare statement opening the file makes it strict: the same text
// in a string or a comment does not
// declare(strict_types=1);

$snippet = 'declare(strict_types=1);';

function takes_int(int $n): int { return $n; }

var_dump(takes_int("5"));
var_dump(strlen(123));

$dir = sys_get_temp_dir() . '/zphp_strict_' . getmypid();
@mkdir($dir);
file_put_contents("$dir/strict.php", "<?php\ndeclare(strict_types=1);\nreturn function () { try { return takes_int('5'); } catch (TypeError \$e) { return \$e->getMessage(); } };\n");
file_put_contents("$dir/off.php", "<?php\ndeclare(strict_types=0);\nreturn function () { return takes_int('6'); };\n");
// the message names the file in the platform's spelling
var_dump(str_replace([$dir, str_replace('/', DIRECTORY_SEPARATOR, $dir)], 'DIR', (require "$dir/strict.php")()));
var_dump((require "$dir/off.php")());
unlink("$dir/strict.php");
unlink("$dir/off.php");
rmdir($dir);
