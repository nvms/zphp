<?php
// user stream wrappers: the wrapper and stream operations php calls on the
// registered class, and in what order

class MemWrapper {
    public static array $files = ['/hello' => "<?php echo 'included: ', __FILE__, \"\\n\"; ?>\nline two\nline three\n"];
    public static array $dirs = ['/' => true];
    public $context;
    private string $name = '';
    private int $pos = 0;
    private array $listing = [];

    private static function key(string $url): string {
        return '/' . ltrim(substr($url, strlen('mem://')), '/');
    }

    function stream_open($path, $mode, $options, &$opened_path) {
        echo "stream_open $path $mode ", $options & STREAM_REPORT_ERRORS ? 'report' : '-', "\n";
        $this->name = self::key($path);
        if ($mode[0] === 'r' && !isset(self::$files[$this->name])) return false;
        if ($mode[0] === 'w') self::$files[$this->name] = '';
        if ($mode[0] === 'a') {
            self::$files[$this->name] ??= '';
        }
        $this->pos = 0;
        return true;
    }
    function stream_read($count) {
        $chunk = substr(self::$files[$this->name], $this->pos, $count);
        $this->pos += strlen($chunk);
        echo "stream_read $count -> ", strlen($chunk), "\n";
        return $chunk;
    }
    function stream_write($data) {
        echo "stream_write ", strlen($data), "\n";
        $f = &self::$files[$this->name];
        $f = substr($f, 0, $this->pos) . $data . substr($f, $this->pos + strlen($data));
        $this->pos += strlen($data);
        return strlen($data);
    }
    function stream_eof() {
        return $this->pos >= strlen(self::$files[$this->name]);
    }
    function stream_tell() {
        echo "stream_tell\n";
        return $this->pos;
    }
    function stream_seek($offset, $whence) {
        echo "stream_seek $offset $whence\n";
        $len = strlen(self::$files[$this->name]);
        $to = match ($whence) { SEEK_SET => $offset, SEEK_CUR => $this->pos + $offset, SEEK_END => $len + $offset };
        if ($to < 0) return false;
        $this->pos = $to;
        return true;
    }
    function stream_flush() {
        echo "stream_flush\n";
        return true;
    }
    function stream_close() {
        echo "stream_close {$this->name}\n";
    }
    function stream_stat() {
        return ['size' => strlen(self::$files[$this->name]), 'mode' => 0100644];
    }
    function url_stat($path, $flags) {
        $k = self::key($path);
        echo "url_stat $k $flags\n";
        if (isset(self::$files[$k])) return ['size' => strlen(self::$files[$k]), 'mode' => 0100644, 'mtime' => 1000];
        if (isset(self::$dirs[$k])) return ['mode' => 040755];
        return false;
    }
    function unlink($path) {
        echo "unlink $path\n";
        $k = self::key($path);
        if (!isset(self::$files[$k])) return false;
        unset(self::$files[$k]);
        return true;
    }
    function rename($from, $to) {
        echo "rename $from $to\n";
        self::$files[self::key($to)] = self::$files[self::key($from)];
        unset(self::$files[self::key($from)]);
        return true;
    }
    function mkdir($path, $mode, $options) {
        printf("mkdir %s %o %d\n", $path, $mode, $options);
        self::$dirs[self::key($path)] = true;
        return true;
    }
    function rmdir($path, $options) {
        echo "rmdir $path $options\n";
        unset(self::$dirs[self::key($path)]);
        return true;
    }
    function dir_opendir($path, $options) {
        echo "dir_opendir $path\n";
        $this->listing = array_map(fn($k) => ltrim($k, '/'), array_keys(self::$files));
        return true;
    }
    function dir_readdir() {
        $e = current($this->listing);
        next($this->listing);
        return $e;
    }
    function dir_rewinddir() {
        echo "dir_rewinddir\n";
        reset($this->listing);
        return true;
    }
    function dir_closedir() {
        echo "dir_closedir\n";
        return true;
    }
    function stream_metadata($path, $option, $value) {
        echo "stream_metadata $path $option ", json_encode($value), "\n";
        return true;
    }
    function stream_truncate(int $size) {
        echo "stream_truncate $size\n";
        self::$files[$this->name] = substr(str_pad(self::$files[$this->name], $size, "\0"), 0, $size);
        return true;
    }
    function stream_lock($op) {
        echo "stream_lock $op\n";
        return true;
    }
    function stream_set_option($option, $arg1, $arg2) {
        echo "stream_set_option $option $arg1 ", var_export($arg2, true), "\n";
        return false;
    }
}

var_dump(stream_wrapper_register('mem', 'MemWrapper'));
var_dump(in_array('mem', stream_get_wrappers()));
var_dump(@stream_wrapper_register('mem', 'MemWrapper'));
var_dump(@stream_wrapper_register('bad scheme', 'MemWrapper'));

$fp = fopen('mem://hello', 'r');
var_dump(fgets($fp));
var_dump(ftell($fp), feof($fp));
var_dump(fseek($fp, 6), fread($fp, 4));
$meta = stream_get_meta_data($fp);
var_dump($meta['wrapper_type'], $meta['stream_type'], $meta['mode'], $meta['seekable'], $meta['uri'], get_class($meta['wrapper_data']));
var_dump(fstat($fp)['size']);
var_dump(flock($fp, LOCK_SH), stream_set_blocking($fp, false), stream_set_timeout($fp, 5), stream_set_write_buffer($fp, 0));
var_dump(fclose($fp));

var_dump(@fopen('mem://missing', 'r'));
$fp = fopen('mem://out', 'w');
var_dump(fwrite($fp, "abc"), fwrite($fp, "defg"), ftell($fp));
var_dump(ftruncate($fp, 2));
fclose($fp);
var_dump(MemWrapper::$files['/out']);
$fp = fopen('mem://out', 'a');
var_dump(ftell($fp));
fwrite($fp, "zz");
unset($fp);

var_dump(file_get_contents('mem://out'));
var_dump(file_put_contents('mem://new', "data"));
var_dump(file('mem://hello', FILE_IGNORE_NEW_LINES));
var_dump(file_exists('mem://new'), is_file('mem://new'), is_dir('mem://'), filesize('mem://new'));
var_dump(file_exists('mem://nothing'));
var_dump(rename('mem://new', 'mem://renamed'), unlink('mem://renamed'), unlink('mem://renamed'));
var_dump(mkdir('mem://d', 0750, true), rmdir('mem://d'));
var_dump(touch('mem://hello', 10, 20), chmod('mem://hello', 0600), chown('mem://hello', 'root'), chgrp('mem://hello', 7));

$d = opendir('mem://');
var_dump(readdir($d), readdir($d));
rewinddir($d);
var_dump(readdir($d));
closedir($d);
var_dump(scandir('mem://'));

include 'mem://hello';
var_dump(stream_wrapper_unregister('mem'), @fopen('mem://hello', 'r'));
var_dump(@stream_wrapper_unregister('mem'));
var_dump(stream_wrapper_unregister('data'), @file_get_contents('data:,x'));
var_dump(stream_wrapper_restore('data'), file_get_contents('data:,x'));
var_dump(@stream_wrapper_restore('data'));
var_dump(@stream_wrapper_restore('mem'));
echo "done\n";
