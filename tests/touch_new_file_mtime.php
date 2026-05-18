<?php
// regression: touch($path, $mtime) applies the explicit timestamp even when
// the file did not exist before the call. previously the create-file branch
// returned without invoking updateTimes so the new file got "now" instead
// of the caller-supplied mtime
$tmp = sys_get_temp_dir() . "/zphp_touch_" . uniqid();
if (file_exists($tmp)) unlink($tmp);

touch($tmp, 1700000000);
echo filemtime($tmp) . "\n";
echo file_exists($tmp) ? "y\n" : "n\n";

// touching again with a new mtime updates the existing file
touch($tmp, 1500000000);
echo filemtime($tmp) . "\n";

// separate atime
touch($tmp, 1600000000, 1650000000);
echo filemtime($tmp) . "\n";
echo fileatime($tmp) . "\n";

unlink($tmp);
