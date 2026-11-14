<?php
// unset($GLOBALS[name]) unsets the global variable, from any scope, and an
// unset in an included file unsets the includer's variable
set_error_handler(function ($no, $msg) { echo "warning: ", $msg, "\n"; return true; });
$x = "x\n";
unset($GLOBALS["x"]);
echo $x;
var_dump(isset($x), array_key_exists('x', $GLOBALS));
function g() {
    unset($GLOBALS["y"]);
    $n = 'z';
    unset($GLOBALS[$n]);
}
$y = 1;
$z = new ArrayObject([1]);
g();
var_dump(isset($y), isset($z));
$y = 2;
var_dump($y, $GLOBALS['y']);
$dir = sys_get_temp_dir() . '/zphp-unset-' . getmypid();
@mkdir($dir);
file_put_contents("$dir/unset.inc", '<?php unset($v);');
$v = 'v';
include "$dir/unset.inc";
echo $v;
var_dump(isset($v), array_key_exists('v', $GLOBALS));
function f($dir) {
    $v = 'local';
    include "$dir/unset.inc";
    echo $v;
    var_dump(isset($v));
}
f($dir);
unlink("$dir/unset.inc");
rmdir($dir);
