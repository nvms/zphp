<?php
error_reporting(0);

// stream_wrapper_unregister + stream_wrapper_restore for builtin
echo "before unregister: " . (in_array('phar', stream_get_wrappers()) ? "y" : "n") . "\n";
echo "unregister phar: " . (stream_wrapper_unregister('phar') ? "y" : "n") . "\n";
echo "after unregister: " . (in_array('phar', stream_get_wrappers()) ? "y" : "n") . "\n";
echo "double-unregister phar: " . (stream_wrapper_unregister('phar') ? "y" : "n") . "\n";
echo "restore phar: " . (stream_wrapper_restore('phar') ? "y" : "n") . "\n";
echo "after restore: " . (in_array('phar', stream_get_wrappers()) ? "y" : "n") . "\n";

// unregistering a non-builtin protocol should fail
echo "unregister bogus: " . (stream_wrapper_unregister('nope') ? "y" : "n") . "\n";

// register a user wrapper backed by a static map
class MemWrapper {
    public $context;
    public static $files = [];
    private $path = '';
    private $pos = 0;

    public function stream_open($path, $mode, $options, &$opened_path) {
        if (!isset(self::$files[$path]) && $mode[0] === 'r') return false;
        $this->path = $path;
        $this->pos = 0;
        if ($mode[0] === 'w') self::$files[$path] = '';
        return true;
    }

    public function stream_read($count) {
        $data = self::$files[$this->path] ?? '';
        $chunk = substr($data, $this->pos, $count);
        $this->pos += strlen($chunk);
        return $chunk;
    }

    public function stream_write($data) {
        self::$files[$this->path] = (self::$files[$this->path] ?? '') . $data;
        $this->pos += strlen($data);
        return strlen($data);
    }

    public function stream_eof() {
        return $this->pos >= strlen(self::$files[$this->path] ?? '');
    }

    public function stream_stat() {
        return ['mode' => 0100644, 'size' => strlen(self::$files[$this->path] ?? '')];
    }

    public function stream_close() {}

    public function url_stat($path, $flags) {
        if (!isset(self::$files[$path])) return false;
        return ['mode' => 0100644, 'size' => strlen(self::$files[$path])];
    }
}

MemWrapper::$files['mem://hello.txt'] = "hi from memory\n";

echo "register mem: " . (stream_wrapper_register('mem', 'MemWrapper') ? "y" : "n") . "\n";
echo "wrappers has mem: " . (in_array('mem', stream_get_wrappers()) ? "y" : "n") . "\n";
echo "double-register mem: " . (stream_wrapper_register('mem', 'MemWrapper') ? "y" : "n") . "\n";

// read via file_get_contents
echo "fgc: " . file_get_contents('mem://hello.txt');
echo "fgc missing: " . var_export(file_get_contents('mem://missing.txt'), true) . "\n";

// existence checks via url_stat
echo "exists hello: " . (file_exists('mem://hello.txt') ? "y" : "n") . "\n";
echo "exists missing: " . (file_exists('mem://missing.txt') ? "y" : "n") . "\n";
echo "is_file hello: " . (is_file('mem://hello.txt') ? "y" : "n") . "\n";
echo "is_dir hello: " . (is_dir('mem://hello.txt') ? "y" : "n") . "\n";

// fopen + fread chunking
$f = fopen('mem://hello.txt', 'r');
echo "chunk: " . fread($f, 5) . "\n";
echo "chunk: " . fread($f, 100) . "\n";
echo "eof: " . (feof($f) ? "y" : "n") . "\n";
fclose($f);

// write + read round trip
$w = fopen('mem://scratch.txt', 'w');
fwrite($w, "scratch contents");
fclose($w);
echo "scratch: " . file_get_contents('mem://scratch.txt') . "\n";

// unregister the user wrapper
echo "unregister mem: " . (stream_wrapper_unregister('mem') ? "y" : "n") . "\n";
echo "wrappers has mem: " . (in_array('mem', stream_get_wrappers()) ? "y" : "n") . "\n";
echo "fgc after unreg: " . var_export(file_get_contents('mem://hello.txt'), true) . "\n";

// restoring a built-in that was never unregistered should still return true
echo "restore active builtin: " . (stream_wrapper_restore('http') ? "y" : "n") . "\n";
