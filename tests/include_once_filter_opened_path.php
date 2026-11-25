<?php
// a file included through php://filter is recorded under its opened path,
// so include_once of the file itself (or of another filter over it) skips it
$dir = sys_get_temp_dir() . '/zphp_inc_filter_' . getmypid();
@mkdir($dir);
$a = realpath($dir) . '/a.php';
$b = realpath($dir) . '/b.php';
file_put_contents($a, '<?php echo "a ran\n";');
file_put_contents($b, '<?php echo "b ran\n";');

var_dump(include_once "php://filter/read=string.rot13|string.rot13/resource=$a");
var_dump(include_once $a);
var_dump(include_once "php://filter/read=string.tolower/resource=$a");
var_dump(include_once $b);
var_dump(include_once "php://filter/read=string.rot13|string.rot13/resource=$b");
foreach (get_included_files() as $f) {
    echo str_replace([realpath($dir), str_replace('/', DIRECTORY_SEPARATOR, realpath($dir))], 'DIR', $f) === $f ? 'main' : str_replace([realpath($dir), str_replace('/', DIRECTORY_SEPARATOR, realpath($dir))], 'DIR', $f), "\n";
}
unlink($a);
unlink($b);
rmdir($dir);
