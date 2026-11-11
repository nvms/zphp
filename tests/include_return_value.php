<?php
// a file without a return statement makes include evaluate to 1; `return;`
// gives null, include_once of a file already included gives true
$dir = sys_get_temp_dir() . "/zphp_include_return_" . getmypid();
@mkdir($dir);
file_put_contents("$dir/plain.php", "<?php\n\$seen = 'plain';\n");
file_put_contents("$dir/bare.php", "<?php\nreturn;\n");
file_put_contents("$dir/value.php", "<?php\nreturn [1, 2];\n");

var_dump(include "$dir/plain.php");
var_dump(require "$dir/plain.php");
var_dump(include "$dir/bare.php");
var_dump(include "$dir/value.php");
var_dump(include_once "$dir/plain.php");
var_dump((include "$dir/plain.php") + 1);
function load($file) {
    return include $file;
}
var_dump(load("$dir/plain.php"), $seen);

foreach (glob("$dir/*") as $file) unlink($file);
rmdir($dir);
