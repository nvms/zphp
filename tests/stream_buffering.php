<?php
// the stream layer's read buffer and positions: what feof, ftell and the
// read functions see as data moves through php's buffer

$file = tempnam(sys_get_temp_dir(), 'zb');
file_put_contents($file, "first line\nsecond line\nthird");

$fp = fopen($file, 'r');
var_dump(fgets($fp), ftell($fp), feof($fp));
var_dump(stream_get_meta_data($fp)['unread_bytes']);
var_dump(fread($fp, 3), ftell($fp));
var_dump(fgetc($fp), ftell($fp));
var_dump(fgets($fp), fgets($fp), feof($fp), fgets($fp));
var_dump(fseek($fp, 6), fread($fp, 4), ftell($fp));
var_dump(fseek($fp, -5, SEEK_END), stream_get_contents($fp), feof($fp));
var_dump(rewind($fp), stream_get_contents($fp, 5), stream_get_contents($fp, 3, 11));
fclose($fp);

// a short read of a plain file reaches eof, of a tmpfile() it does not
$fp = fopen($file, 'r');
var_dump(strlen(fread($fp, 1000)), feof($fp));
$tmp = tmpfile();
fwrite($tmp, "abc");
rewind($tmp);
var_dump(fread($tmp, 10), feof($tmp), fread($tmp, 10), feof($tmp));

// stream_get_line
$fp = fopen($file, 'r');
var_dump(stream_get_line($fp, 100, "\n"), stream_get_line($fp, 4), stream_get_line($fp, 100, "line"), stream_get_line($fp, 0, "\n"));
var_dump(stream_get_line($fp, 100, "\n"), stream_get_line($fp, 100, "\n"));
fclose($fp);

// append mode: the position counts from where the stream opened
$fp = fopen($file, 'a+');
var_dump(ftell($fp), fwrite($fp, "!!"), ftell($fp));
rewind($fp);
var_dump(fgets($fp), ftell($fp));
fwrite($fp, "??");
var_dump(ftell($fp));
fclose($fp);
var_dump(file_get_contents($file));

// read and write on one stream: a write lands at the logical position
$fp = fopen($file, 'r+');
var_dump(fread($fp, 5));
fwrite($fp, "XX");
var_dump(ftell($fp));
rewind($fp);
var_dump(fgets($fp));
fclose($fp);

// php://memory and php://temp
$m = fopen('php://memory', 'w+');
fwrite($m, "12345");
var_dump(fseek($m, 10), ftell($m), fwrite($m, "x"), ftell($m));
rewind($m);
var_dump(bin2hex(stream_get_contents($m)));
var_dump(fseek($m, -100, SEEK_CUR), ftell($m));
var_dump(fseek($m, 2), fread($m, 2), feof($m), fread($m, 100), feof($m));
var_dump(ftruncate($m, 3), ftell($m), fstat($m)['size']);
rewind($m);
var_dump(stream_get_contents($m));
$ro = fopen('php://memory', 'r');
var_dump(fwrite($ro, "nope"));
$ap = fopen('php://temp', 'a');
fwrite($ap, "one");
rewind($ap);
fwrite($ap, "two");
rewind($ap);
var_dump(stream_get_contents($ap));
var_dump(stream_get_meta_data($ap)['mode'], stream_get_meta_data($m)['stream_type']);

// stream_copy_to_stream
$src = fopen($file, 'r');
$dst = fopen('php://memory', 'w+');
var_dump(stream_copy_to_stream($src, $dst, 5), stream_copy_to_stream($src, $dst, null, 6), ftell($src), feof($src));
rewind($dst);
var_dump(stream_get_contents($dst));
var_dump(stream_copy_to_stream($src, $dst));

// chunk size and read buffer
$fp = fopen($file, 'r');
var_dump(stream_set_chunk_size($fp, 4), stream_set_chunk_size($fp, 8192));
var_dump(stream_set_read_buffer($fp, 0), fread($fp, 3), stream_get_meta_data($fp)['unread_bytes']);
try {
    stream_set_chunk_size($fp, 0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    stream_get_line($fp, -1);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    stream_get_contents($fp, -2);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
fclose($fp);

// a data: stream
$d = fopen('data://text/plain;base64,SGVsbG8gZGF0YQ==', 'r');
var_dump(fread($d, 5), ftell($d), stream_get_contents($d), feof($d));
var_dump(fwrite($d, "x"));

unlink($file);
echo "done\n";
