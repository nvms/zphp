<?php
// regression: fopen emits a PHP-format Warning on failure ('Failed to open
// stream: <reason>') instead of returning false silently. exercises three
// reason mappings: missing file, exclusive-create collision, and missing
// dir. also covers stream_supports_lock returning true for local files and
// false for the php:// stream family

// nonexistent file: 'No such file or directory'
var_dump(fopen("/nonexistent/dir/file.txt", "r"));

// exclusive-create collision: 'File exists' (path printed verbatim so use a
// deterministic name; both runs see the same fopen() warning text)
$tmp = "/tmp/zphp_fopen_excl_fixed.txt";
@unlink($tmp);
$fp = fopen($tmp, "x");
fwrite($fp, "x");
fclose($fp);
var_dump(fopen($tmp, "x"));
unlink($tmp);

// stream_supports_lock: true for local files, false for php:// streams
$real = tempnam(sys_get_temp_dir(), "zphp_l_");
$f = fopen($real, "r+");
var_dump(stream_supports_lock($f));
fclose($f);
unlink($real);

$mem = fopen("php://memory", "r+");
var_dump(stream_supports_lock($mem));
fclose($mem);

$tmpf = fopen("php://temp", "r+");
var_dump(stream_supports_lock($tmpf));
fclose($tmpf);
