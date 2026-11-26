<?php
// CURLOPT_FILE, _WRITEHEADER, _INFILE and _STDERR take streams: the body,
// headers, upload and verbose log go through them
$dir = sys_get_temp_dir() . '/zphp-curlstream-' . getmypid();
@mkdir($dir);
$src = "$dir/src.txt";
file_put_contents($src, str_repeat("line of text\n", 300));

$ch = curl_init("file://$src");
foreach ([CURLOPT_FILE, CURLOPT_WRITEHEADER, CURLOPT_STDERR, CURLOPT_INFILE] as $opt) {
    $r = fopen($src, 'r');
    try {
        var_dump(curl_setopt($ch, $opt, $r));
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
    fclose($r);
}
foreach (["x", 42, fopen('php://memory', 'r+')] as $bad) {
    try {
        var_dump(curl_setopt($ch, CURLOPT_FILE, $bad));
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$closed = fopen('php://memory', 'w');
fclose($closed);
try {
    curl_setopt($ch, CURLOPT_FILE, $closed);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

// the body goes to the file's descriptor, past the stream's own position
$out = "$dir/out.txt";
$w = fopen($out, 'w');
fwrite($w, "before\n");
var_dump(curl_setopt($ch, CURLOPT_FILE, $w));
var_dump(curl_exec($ch));
var_dump(ftell($w));
fwrite($w, "after\n");
fclose($w);
$got = file_get_contents($out);
var_dump(strlen($got), substr($got, 0, 20), substr($got, -19));

// a memory stream gets them through its own writes
$m = fopen('php://memory', 'w+');
$h = fopen('php://memory', 'w+');
curl_setopt_array($ch, [CURLOPT_FILE => $m, CURLOPT_WRITEHEADER => $h, CURLOPT_HEADER => false]);
var_dump(curl_exec($ch), ftell($m));
rewind($m);
var_dump(strlen(stream_get_contents($m)));
rewind($h);
rewind($h);
var_dump(preg_grep("/^Content-Length/", explode("\r\n", stream_get_contents($h))));

// RETURNTRANSFER takes over from the file again
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
var_dump(strlen(curl_exec($ch)), ftell($m));

// a closed stream is dropped with a warning when the transfer runs
$gone = fopen('php://memory', 'w+');
curl_setopt($ch, CURLOPT_FILE, $gone);
fclose($gone);
ob_start();
var_dump(curl_exec($ch));
$shown = ob_get_clean();
var_dump(strlen($shown));
$h2 = fopen('php://memory', 'w+');
curl_setopt($ch, CURLOPT_WRITEHEADER, $h2);
fclose($h2);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
var_dump(strlen(curl_exec($ch)));

// an upload reads the INFILE stream
$up = curl_init("file://$dir/uploaded.txt");
$in = fopen('php://memory', 'w+');
fwrite($in, "uploaded through a memory stream\n");
rewind($in);
curl_setopt_array($up, [CURLOPT_UPLOAD => true, CURLOPT_INFILE => $in, CURLOPT_INFILESIZE => 33]);
var_dump(curl_exec($up));
var_dump(file_get_contents("$dir/uploaded.txt"));
$fin = fopen($src, 'r');
curl_setopt($up, CURLOPT_INFILE, $fin);
curl_setopt($up, CURLOPT_INFILESIZE, filesize($src));
var_dump(curl_exec($up), filesize("$dir/uploaded.txt"), ftell($fin));
fclose($fin);
var_dump(curl_exec($up));

// the verbose log goes to the STDERR stream
$log = fopen("php://memory", "w+");
$v = curl_init("file://$src");
curl_setopt_array($v, [CURLOPT_VERBOSE => true, CURLOPT_STDERR => $log, CURLOPT_RETURNTRANSFER => true]);
curl_exec($v);
$logfile = "$dir/log.txt";
$lf = fopen($logfile, 'w');
curl_setopt($v, CURLOPT_STDERR, $lf);
curl_exec($v);
fclose($lf);
var_dump(filesize($logfile) > 0);

foreach (['src.txt', 'out.txt', 'uploaded.txt', 'log.txt'] as $f) @unlink("$dir/$f");
rmdir($dir);
