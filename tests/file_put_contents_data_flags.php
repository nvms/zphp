<?php
// file_put_contents checks its arguments, writes what each kind of data
// turns into, and reports why a path cannot be opened
class Stringy { function __toString() { return "from toString"; } }
class Plain {}

$file = sys_get_temp_dir() . "/zphp_fpc_" . getmypid();
$context = stream_context_create();

try {
    file_put_contents($file, $context);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$fp = fopen(__FILE__, "r");
try {
    file_put_contents($file, "x", 0, $fp);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
fclose($fp);
try {
    file_put_contents("", "x");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

var_dump(file_put_contents($file, new Stringy), file_get_contents($file));
var_dump(file_put_contents($file, new Plain), file_get_contents($file));
var_dump(file_put_contents($file, [1, 2.5, true, null, "s", new Stringy]), file_get_contents($file));
var_dump(file_put_contents($file, ["a", [1]]), file_get_contents($file));
try {
    file_put_contents($file, ["a", new Plain]);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(file_put_contents($file, 12.5), file_put_contents($file, "more", FILE_APPEND), file_get_contents($file));
var_dump(file_put_contents($file, "locked", LOCK_EX), file_get_contents($file));
var_dump(file_put_contents("php://memory", "x", LOCK_EX));

$src = fopen("php://memory", "w+");
fwrite($src, "streamed data");
fseek($src, 3);
var_dump(file_put_contents($file, $src), file_get_contents($file));

var_dump(file_put_contents("/zphp_no_such_dir/f", "x"));
var_dump(file_put_contents("file://relative", "x"));
unlink($file);
