<?php
// a popen() stream is php's STDIO stream over the pipe: the mode as written,
// not seekable, with neither a wrapper type nor a uri

foreach (['r', 'rb'] as $mode) {
    $handle = popen('echo here is some output', $mode);
    $data = fread($handle, 100);
    var_dump(trim($data), stream_get_meta_data($handle));
    pclose($handle);
}
$handle = popen('cat > ' . (DIRECTORY_SEPARATOR === '\\' ? 'NUL' : '/dev/null'), 'w');
var_dump(stream_get_meta_data($handle));
pclose($handle);
