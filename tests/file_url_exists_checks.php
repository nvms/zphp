<?php
// the exists checks and stat calls take file:// urls for local paths
$dir = 'file://' . sys_get_temp_dir() . '/zphp_fileurl_dir_' . getmypid();
var_dump(mkdir($dir), is_dir($dir), file_exists($dir), is_file($dir), is_readable($dir), is_writable($dir));
var_dump(filetype($dir), is_array(stat($dir)));
touch("$dir/f");
var_dump(is_file("$dir/f"), filesize("$dir/f"), is_file("file://localhost" . substr($dir, 7) . "/f"));
var_dump(file_exists("file://somehost/tmp"), is_dir("file://somehost/tmp"));
var_dump(unlink("$dir/f"), rmdir($dir), is_dir($dir));
