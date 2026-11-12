<?php
// stream_is_local asks the wrapper behind a path or a stream

var_dump(stream_is_local('/tmp/file'));
var_dump(stream_is_local('file:///tmp/file'));
var_dump(stream_is_local('phar:///tmp/archive.phar/file'));
var_dump(stream_is_local('https://example.com/file'));

class Remote {
    public $context;
    function stream_open($path, $mode, $options, &$opened) { return true; }
    function stream_eof() { return true; }
}
stream_wrapper_register('remote', 'Remote', STREAM_IS_URL);
stream_wrapper_register('near', 'Remote');

$n = 1;
var_dump(stream_is_local($n), $n);
foreach (['/etc/passwd', 'file:///tmp', 'php://memory', 'compress.zlib://x', 'http://example.com',
          'HTTPS://example.com', 'ftp://x', 'data:,abc', 'data://text/plain,x', 'glob://*',
          'nosuch://x', 'remote://x', 'near://x', ''] as $p) {
    echo $p, ': ';
    var_dump(stream_is_local($p));
}

var_dump(stream_is_local(fopen(__FILE__, 'r')));
var_dump(stream_is_local(fopen('php://memory', 'r')));
var_dump(stream_is_local(fopen('data:,x', 'r')));
var_dump(stream_is_local(STDIN));
var_dump(stream_is_local(tmpfile()));
var_dump(stream_is_local(opendir(__DIR__)));
var_dump(stream_is_local(fopen('remote://a', 'r')));
var_dump(stream_is_local(fopen('near://a', 'r')));
$p = popen('echo x', 'r');
var_dump(stream_is_local($p));
fgets($p);
pclose($p);
$srv = stream_socket_server('tcp://127.0.0.1:0');
var_dump(stream_is_local($srv));
