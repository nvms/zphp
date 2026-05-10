<?php
$f = fopen("php://memory", "w+");
// gettype is "resource" in PHP, "object" in zphp (architectural - FileHandle)
fwrite($f, "hello");
echo ftell($f), "\n";
rewind($f);
echo fread($f, 100), "\n";

fwrite($f, " world");
rewind($f);
echo fread($f, 100), "\n";

ftruncate($f, 0);
fwrite($f, "fresh");
rewind($f);
echo fread($f, 100), "\n";
fclose($f);

$f = fopen("php://memory", "r+");
// gettype is "resource" in PHP, "object" in zphp (architectural - FileHandle)
fwrite($f, "abc");
rewind($f);
echo fread($f, 100), "\n";
fclose($f);

$f = fopen("php://temp", "w+");
fwrite($f, "temp data");
rewind($f);
echo fread($f, 100), "\n";
fclose($f);

$f = fopen("php://temp/maxmemory:1024", "w+");
fwrite($f, "small");
rewind($f);
echo fread($f, 100), "\n";
fclose($f);

ob_start();
$f = fopen("php://output", "w");
fwrite($f, "output\n");
fclose($f);
$out = ob_get_clean();
echo "captured=", $out;

$ctx = stream_context_create([]);
// stream_context_create returns "resource" in PHP, "object" in zphp (architectural)

$f = fopen("php://memory", "w+");
fwrite($f, "line1\nline2\nline3\n");
rewind($f);
while (($line = fgets($f)) !== false) {
    echo "[", trim($line), "]";
}
echo "\n";
fclose($f);

$path = sys_get_temp_dir() . "/zphp_ctx_" . getmypid();
file_put_contents($path, "world");

$ctx = stream_context_create([]);
$content = file_get_contents($path, false, $ctx);
echo $content, "\n";

$f = fopen($path, "r", false, $ctx);
// gettype is "resource" in PHP, "object" in zphp (architectural)
echo fread($f, 100), "\n";
fclose($f);
unlink($path);

$ctx = stream_context_create(["http" => ["method" => "GET", "timeout" => 5]]);
// stream_context_create returns "resource" in PHP, "object" in zphp (architectural)

$f = fopen("php://memory", "w+");
fputs($f, "alias-fputs");
rewind($f);
echo fgets($f), "\n";
fclose($f);

$f = fopen("php://memory", "w+");
fwrite($f, "0123456789");
fseek($f, 0);
echo fgetc($f), fgetc($f), fgetc($f), "\n";
fseek($f, 5);
echo fread($f, 5), "\n";
fseek($f, -2, SEEK_END);
echo fread($f, 100), "\n";
fclose($f);

$f = fopen("php://memory", "w+");
fwrite($f, "test eof\n");
rewind($f);
fread($f, 100);
var_dump(feof($f));
fclose($f);

$f = fopen("php://memory", "w+");
$copies = stream_copy_to_stream(
    (function () { $g = fopen("php://memory", "w+"); fwrite($g, "src-data"); rewind($g); return $g; })(),
    $f,
);
echo "copied=$copies\n";
rewind($f);
echo fread($f, 100), "\n";
fclose($f);

$f = fopen("php://memory", "w+");
fwrite($f, "stream-content");
rewind($f);
echo stream_get_contents($f), "\n";
fclose($f);

$f = fopen("php://memory", "w+");
fwrite($f, "0123456789");
echo stream_get_contents($f, 5, 3), "\n";
fclose($f);

$inputs = ["alpha", "beta", "gamma"];
foreach ($inputs as $val) {
    $f = fopen("php://memory", "w+");
    fwrite($f, $val);
    rewind($f);
    echo fread($f, 100), " ";
    fclose($f);
}
echo "\n";

$path = sys_get_temp_dir() . "/zphp_ctx_get_" . getmypid();
file_put_contents($path, "abcdefghij");
echo file_get_contents($path, false, null, 2, 5), "\n";
echo file_get_contents($path, false, null, 0, 3), "\n";
echo file_get_contents($path, false, null, 8), "\n";
unlink($path);

$f = fopen("php://memory", "w+");
$meta = stream_get_meta_data($f);
echo gettype($meta), "\n";
fclose($f);

$f = fopen("php://memory", "w+");
echo stream_set_blocking($f, false) ? "y" : "n", "\n";
echo stream_set_blocking($f, true) ? "y" : "n", "\n";
fclose($f);
