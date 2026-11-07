<?php
// an error inside an included file ends include exactly as it ends require;
// include differs only when the file can't be opened
$dir = sys_get_temp_dir() . '/zphp_include_error';
@mkdir($dir);
file_put_contents("$dir/throws.php", '<?php throw new RuntimeException("from include");');
file_put_contents("$dir/Broken.php", '<?php undefined_function(); class Broken {}');
register_shutdown_function(function () use ($dir) {
    @unlink("$dir/throws.php");
    @unlink("$dir/Broken.php");
    @rmdir($dir);
});

try {
    include "$dir/throws.php";
} catch (RuntimeException $e) {
    echo "caught: ", $e->getMessage(), "\n";
}
function load($file) { return include $file; }
try {
    load("$dir/throws.php");
} catch (RuntimeException $e) {
    echo "caught in function: ", $e->getMessage(), "\n";
}
var_dump(@include "$dir/missing.php");

spl_autoload_register(function ($class) use ($dir) { include "$dir/$class.php"; });
var_dump(class_exists('Broken'));
echo "not reached\n";
