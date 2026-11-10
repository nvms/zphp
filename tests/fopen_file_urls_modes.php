<?php
// file:// urls name local paths only without a host, fopen checks its mode
// and its path, and an unregistered file:// wrapper leaves nothing to open
$file = sys_get_temp_dir() . "/zphp_fileurl_test";
file_put_contents($file, "content");

foreach (["file://$file", "file://localhost$file", "file:////$file"] as $url) {
    $fp = fopen($url, "r");
    var_dump(fread($fp, 100), stream_supports_lock($fp));
    fclose($fp);
    var_dump(file_get_contents($url));
}
var_dump(fopen("file://relative/path", "r"));
var_dump(file_get_contents("file://relative/path"));
var_dump(fopen($file, "Q"), fopen($file, ""));
try {
    fopen("", "r");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    fopen("a\0b", "r");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(stream_supports_lock(fopen("data://text/plain,abc", "r")));

var_dump(stream_wrapper_unregister("file"));
var_dump(fopen("file://$file", "r"));
var_dump(stream_wrapper_restore("file"));
var_dump(is_resource(fopen("file://$file", "r")));
unlink($file);
