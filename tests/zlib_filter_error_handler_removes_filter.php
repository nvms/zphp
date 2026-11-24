<?php
// an error handler that removes a failing zlib.inflate filter from inside
// the filter's data error notice: the filter is done with its state by then
$fp = fopen('php://memory', 'w+');
$filter = stream_filter_append($fp, 'zlib.inflate', STREAM_FILTER_WRITE);
set_error_handler(function (int $errno, string $errstr) use (&$filter) {
    echo $errstr, "\n";
    var_dump(stream_filter_remove($filter));
    return true;
});
var_dump(fwrite($fp, "\xff\xff\xff\xff"));
var_dump(fwrite($fp, "plain"));
rewind($fp);
var_dump(stream_get_contents($fp));

$fp = fopen('php://memory', 'w+');
fwrite($fp, "\xff\xff\xff\xff");
rewind($fp);
$filter = stream_filter_append($fp, 'zlib.inflate', STREAM_FILTER_READ);
var_dump(fread($fp, 10));
var_dump(fread($fp, 10));
restore_error_handler();

// without a handler the filter stays and fails again
$fp = fopen('php://memory', 'w+');
stream_filter_append($fp, 'zlib.inflate', STREAM_FILTER_WRITE);
var_dump(@fwrite($fp, "\xff\xff\xff\xff"));
echo error_get_last()['message'], "\n";
echo "Done\n";
