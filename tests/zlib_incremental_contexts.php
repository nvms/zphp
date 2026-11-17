<?php
// deflate_init/deflate_add and inflate_init/inflate_add: incremental
// compression in each encoding, flush modes, options and their errors

function attempt(callable $f) {
    try {
        $r = $f();
        var_dump($r);
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

$text = str_repeat("The quick brown fox jumps over the lazy dog. ", 200);
foreach ([ZLIB_ENCODING_RAW, ZLIB_ENCODING_DEFLATE, ZLIB_ENCODING_GZIP] as $encoding) {
    $d = deflate_init($encoding, ['level' => 9]);
    var_dump(get_class($d));
    $packed = '';
    foreach (str_split($text, 1000) as $chunk) {
        $packed .= deflate_add($d, $chunk, ZLIB_NO_FLUSH);
    }
    $packed .= deflate_add($d, '', ZLIB_FINISH);
    $i = inflate_init($encoding);
    $plain = '';
    foreach (str_split($packed, 100) as $chunk) {
        $plain .= inflate_add($i, $chunk);
    }
    var_dump($plain === $text, inflate_get_status($i) === ZLIB_STREAM_END, inflate_get_read_len($i) === strlen($packed));
    // the context starts over after a finished stream
    $again = deflate_add($d, 'abc', ZLIB_FINISH);
    var_dump(inflate_add(inflate_init($encoding), $again, ZLIB_FINISH));
}

// one-shot results match the matching functions
var_dump(deflate_add(deflate_init(ZLIB_ENCODING_DEFLATE), 'hello', ZLIB_FINISH) === gzcompress('hello'));
var_dump(deflate_add(deflate_init(ZLIB_ENCODING_RAW), 'hello', ZLIB_FINISH) === gzdeflate('hello'));
var_dump(bin2hex(deflate_add(deflate_init(ZLIB_ENCODING_DEFLATE), 'sync')));
var_dump(deflate_add(deflate_init(ZLIB_ENCODING_DEFLATE), ''));

// dictionaries
$dict = ['quick', 'brown', 'lazy'];
$d = deflate_init(ZLIB_ENCODING_DEFLATE, ['dictionary' => $dict]);
$packed = deflate_add($d, 'the quick brown fox and the lazy dog', ZLIB_FINISH);
var_dump(inflate_add(inflate_init(ZLIB_ENCODING_DEFLATE, ['dictionary' => $dict]), $packed));
attempt(fn () => inflate_add(inflate_init(ZLIB_ENCODING_DEFLATE), $packed));
attempt(fn () => inflate_add(inflate_init(ZLIB_ENCODING_DEFLATE, ['dictionary' => 'other']), $packed));
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['dictionary' => ['a', '']]));
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['dictionary' => ["a\0b"]]));
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['dictionary' => 5]));

// option and argument errors
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['level' => 10]));
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['memory' => 0]));
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['window' => 7]));
attempt(fn () => deflate_init(ZLIB_ENCODING_DEFLATE, ['strategy' => 42]));
attempt(fn () => deflate_init(42));
attempt(fn () => inflate_init(42));
attempt(fn () => inflate_init(ZLIB_ENCODING_DEFLATE, ['window' => 16]));
attempt(fn () => deflate_add(deflate_init(ZLIB_ENCODING_DEFLATE), 'x', 42));
attempt(fn () => inflate_add(inflate_init(ZLIB_ENCODING_DEFLATE), 'x', 42));
attempt(fn () => deflate_add(inflate_init(ZLIB_ENCODING_DEFLATE), 'x'));
attempt(fn () => inflate_add(inflate_init(ZLIB_ENCODING_DEFLATE), 'not compressed'));
attempt(fn () => new DeflateContext());
attempt(fn () => new InflateContext());
attempt(fn () => clone deflate_init(ZLIB_ENCODING_DEFLATE));
attempt(fn () => serialize(deflate_init(ZLIB_ENCODING_DEFLATE)));

// a small window and other strategies round-trip
foreach ([ZLIB_FILTERED, ZLIB_HUFFMAN_ONLY, ZLIB_RLE, ZLIB_FIXED, ZLIB_DEFAULT_STRATEGY] as $strategy) {
    $d = deflate_init(ZLIB_ENCODING_GZIP, ['strategy' => $strategy, 'window' => 9, 'memory' => 1]);
    $packed = deflate_add($d, $text, ZLIB_FINISH);
    var_dump(inflate_add(inflate_init(ZLIB_ENCODING_GZIP, ['window' => 9]), $packed) === $text);
}
var_dump(ZLIB_NO_FLUSH, ZLIB_PARTIAL_FLUSH, ZLIB_SYNC_FLUSH, ZLIB_FULL_FLUSH, ZLIB_BLOCK, ZLIB_FINISH);
var_dump(ZLIB_OK, ZLIB_STREAM_END, ZLIB_NEED_DICT, ZLIB_ERRNO, ZLIB_STREAM_ERROR, ZLIB_DATA_ERROR, ZLIB_MEM_ERROR, ZLIB_BUF_ERROR, ZLIB_VERSION_ERROR);
echo implode(',', array_keys((new ReflectionExtension('zlib'))->getClasses())), "\n";
