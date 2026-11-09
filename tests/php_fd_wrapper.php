<?php
// php://fd/N duplicates a descriptor and ignores the mode; bad urls get
// php's wrapper errors
echo "before\n";
$out = fopen("php://fd/1", "rkkk");
fwrite($out, "through fd 1\n");
echo "after\n";

$file = sys_get_temp_dir() . "/zphp_fd_" . getmypid();
$h = fopen($file, "w+");
$meta = stream_get_meta_data(fopen("php://fd/1", "w"));
var_dump($meta['uri'] ?? null);

var_dump(fopen("php://fd", "w"));
var_dump(fopen("php://fd/", "w"));
var_dump(fopen("php://fd/1/", "w"));
var_dump(fopen("php://fd/x", "w"));
var_dump(fopen("php://fd/-2", "w") === false);
var_dump(fopen("php://nonsense", "r"));
fclose($h);
unlink($file);
