<?php
// a stream opened through a file:// url, in any case, reports that url as
// its uri and is a plain file
$f = sys_get_temp_dir() . '/zphp_file_url_' . getmypid() . '.txt';
foreach (['File://' . $f, 'file://' . $f, 'FILE://' . $f, $f] as $p) {
    $fp = fopen($p, 'w+');
    $m = stream_get_meta_data($fp);
    echo str_replace([$f, str_replace('/', DIRECTORY_SEPARATOR, $f)], 'FILE', $m['uri']), ' ', $m['wrapper_type'], ' ', $m['stream_type'], ' ', var_export(stream_is_local($fp), true), "\n";
    fclose($fp);
}
unlink($f);
