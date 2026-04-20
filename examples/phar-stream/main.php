<?php
// covers: file_get_contents, file_exists, is_file, is_dir, fopen, fread,
//   fclose, base64_decode, sys_get_temp_dir, file_put_contents, json_decode,
//   in_array, stream_get_wrappers, mt_rand,
//   phar:// stream wrapper

// pre-built phar containing app/main.php, app/config.json, app/lib/util.php
$pharB64 = 'PD9waHAKZWNobyAic3R1YiIuUEhQX0VPTDsKX19IQUxUX0NPTVBJTEVSKCk7ID8+DQq+AAAABAAAABEAAAABAAkAAAB0ZXN0LnBoYXIAAAAACQAAAHJlYWRtZS5tZAsAAABGNOZpCwAAAFIUCsSkAQAAAAAAAAwAAABsaWIvdXRpbC5waHAiAAAARjTmaSIAAACv9V+LpAEAAAAAAAAQAAAAZGF0YS9jb25maWcuanNvbg8AAABGNOZpDwAAANLfIEqkAQAAAAAAAA4AAABhL2IvYy9kZWVwLnR4dAUAAABGNOZpBQAAAIK4niekAQAAAAAAAEhlbGxvIHBoYXIKPD9waHAKZnVuY3Rpb24gZigpIHsgcmV0dXJuIDQyOyB9CnsibmFtZSI6InRlc3QifWRlZXAKn/k37nhii0YNsBJgRAAI+Z9UXDqSbCjBI8PUu+5Ro+4DAAAAR0JNQg==';

$pharFile = sys_get_temp_dir() . '/zphp_example_' . mt_rand(1000000, 9999999) . '.phar';
file_put_contents($pharFile, base64_decode($pharB64));

// confirm wrapper is registered
echo "phar wrapper: " . (in_array('phar', stream_get_wrappers()) ? "registered" : "missing") . "\n";

// inspect what the phar contains
$paths = ['readme.md', 'lib/util.php', 'data/config.json', 'a/b/c/deep.txt'];
foreach ($paths as $path) {
    $url = "phar://$pharFile/$path";
    if (file_exists($url) && is_file($url)) {
        echo "$path: " . strlen(file_get_contents($url)) . " bytes\n";
    }
}

// load the readme line by line
echo "--- readme ---\n";
$f = fopen("phar://$pharFile/readme.md", 'r');
while (!feof($f)) {
    $line = fread($f, 1024);
    if ($line === false || $line === '') break;
    echo $line;
}
fclose($f);

// parse json config from inside the phar
$cfg = json_decode(file_get_contents("phar://$pharFile/data/config.json"), true);
echo "config name: " . $cfg['name'] . "\n";

// dir checks
echo "lib is_dir: " . (is_dir("phar://$pharFile/lib") ? "yes" : "no") . "\n";
echo "a/b is_dir: " . (is_dir("phar://$pharFile/a/b") ? "yes" : "no") . "\n";

@unlink($pharFile);
