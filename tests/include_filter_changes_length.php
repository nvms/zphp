<?php
// include through a read filter that changes the code's length reads the
// stream to its end, not the file's stat size
class Lengthen extends php_user_filter {
    private $data = '';
    public function filter($in, $out, &$consumed, $closing): int {
        while ($bucket = stream_bucket_make_writeable($in)) {
            $this->data .= $bucket->data;
        }
        if ($closing || feof($this->stream)) {
            $consumed = strlen($this->data);
            $bucket = stream_bucket_new($this->stream, str_replace('short', 'much longer text', $this->data));
            stream_bucket_append($out, $bucket);
            return PSFS_PASS_ON;
        }
        return PSFS_FEED_ME;
    }
}
stream_filter_register('test.lengthen', 'Lengthen');
$file = sys_get_temp_dir() . '/zphp_include_filter_' . getmypid() . '.php';
file_put_contents($file, "<?php\nif (true) {\n    echo 'short', PHP_EOL;\n    echo 'short', PHP_EOL;\n}\nreturn 'short';\n");
var_dump(include 'php://filter/read=test.lengthen/resource=' . $file);
var_dump(include 'php://filter/read=string.rot13|string.rot13/resource=' . $file);
// the included code runs under its resource's own path, as php's
// php://filter hands back the opened path
file_put_contents($file, "<?php\nreturn [__FILE__, __DIR__, __LINE__];\n");
[$f, $d, $l] = include 'php://filter/read=string.rot13|string.rot13/resource=' . $file;
var_dump($f === realpath($file), $d === dirname(realpath($file)), $l);
[$f] = include 'php://filter/read=string.rot13/resource=php://filter/read=string.rot13/resource=file://' . $file;
var_dump($f === realpath($file));
unlink($file);
