<?php
// php 8.6's filter seeking: a seek asks every filter on the stream first
// (convert, zlib, dechunk and consumed reads only to the start, a write
// chain per its write_seek_mode), and the stateful filters start over when
// the stream moves; a user filter's seek($offset, $whence, $chain) decides
set_error_handler(function ($no, $msg) { echo "warning: $msg\n"; return true; });
$file = sys_get_temp_dir() . '/zphp_filter_seek_' . getmypid() . '.txt';

file_put_contents($file, base64_encode("Hello World! This is a test of seeking."));
$fp = fopen($file, 'r');
stream_filter_append($fp, 'convert.base64-decode', STREAM_FILTER_READ);
echo fread($fp, 12), "\n";
var_dump(fseek($fp, 0, SEEK_SET));
echo fread($fp, 12), "\n";
var_dump(fseek($fp, 5, SEEK_SET));
fclose($fp);

class Counting extends php_user_filter {
    private $count = 0;
    public static $log = [];
    public function filter($in, $out, &$consumed, bool $closing): int {
        while ($bucket = stream_bucket_make_writeable($in)) {
            $modified = '';
            for ($i = 0; $i < strlen($bucket->data); $i++) {
                $modified .= $bucket->data[$i] . $this->count++;
            }
            $bucket->data = $modified;
            $consumed += $bucket->datalen;
            stream_bucket_append($out, $bucket);
        }
        return PSFS_PASS_ON;
    }
    public function seek(int $offset, int $whence, int $chain): bool {
        self::$log[] = "$offset:$whence:" . ($chain === STREAM_FILTER_READ ? "read" : "write");
        if ($offset === 0 && $whence === SEEK_SET) {
            $this->count = 0;
            return true;
        }
        return false;
    }
}
class NoSeek extends php_user_filter {
    public function filter($in, $out, &$consumed, bool $closing): int {
        while ($bucket = stream_bucket_make_writeable($in)) {
            $consumed += $bucket->datalen;
            stream_bucket_append($out, $bucket);
        }
        return PSFS_PASS_ON;
    }
}
stream_filter_register('test.counting', 'Counting');
stream_filter_register('test.noseek', 'NoSeek');

file_put_contents($file, 'ABC');
$fp = fopen($file, 'r');
stream_filter_append($fp, 'test.counting', STREAM_FILTER_READ);
echo fread($fp, 10), "\n";
var_dump(fseek($fp, 0, SEEK_SET));
echo fread($fp, 10), "\n";
var_dump(fseek($fp, 1, SEEK_SET));
fclose($fp);
echo implode(",", Counting::$log), "\n";

$fp = fopen($file, 'r');
stream_filter_append($fp, 'test.noseek', STREAM_FILTER_READ);
echo fread($fp, 10), "\n";
var_dump(fseek($fp, 1, SEEK_SET), fread($fp, 10));
fclose($fp);

foreach (['preserve', 'reset', 'strict', 'bogus'] as $mode) {
    $fp = fopen($file, 'w+');
    $f = stream_filter_append($fp, 'convert.base64-encode', STREAM_FILTER_WRITE, ['write_seek_mode' => $mode]);
    echo "$mode: ", var_export($f !== false, true), "\n";
    fwrite($fp, "abc");
    var_dump(fseek($fp, 0, SEEK_SET), fseek($fp, 2, SEEK_SET));
    fclose($fp);
}

$fp = fopen($file, 'w+');
stream_filter_append($fp, 'zlib.deflate', STREAM_FILTER_WRITE);
fwrite($fp, str_repeat("zlib ", 20));
var_dump(fseek($fp, 0, SEEK_SET));
fclose($fp);
$fp = fopen($file, 'r');
stream_filter_append($fp, 'string.rot13', STREAM_FILTER_READ);
var_dump(fseek($fp, 3, SEEK_SET));
fclose($fp);
unlink($file);
