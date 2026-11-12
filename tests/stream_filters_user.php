<?php
// user stream filters: php_user_filter, the bucket brigade api, chains

class upper_filter extends php_user_filter {
    public function filter($in, $out, &$consumed, bool $closing): int {
        while ($bucket = stream_bucket_make_writeable($in)) {
            $bucket->data = strtoupper($bucket->data);
            $consumed += $bucket->datalen;
            stream_bucket_append($out, $bucket);
        }
        return PSFS_PASS_ON;
    }
}

class tracing_filter extends php_user_filter {
    public function onCreate(): bool {
        echo "onCreate {$this->filtername} ", var_export($this->params, true), "\n";
        return true;
    }
    public function onClose(): void {
        echo "onClose {$this->filtername}\n";
    }
    public function filter($in, $out, &$consumed, bool $closing): int {
        echo "filter closing=", var_export($closing, true), " stream=", get_resource_type($this->stream), "\n";
        while ($bucket = stream_bucket_make_writeable($in)) {
            echo "  bucket ", strlen($bucket->data), " ", $bucket->datalen, "\n";
            $consumed += $bucket->datalen;
            stream_bucket_append($out, $bucket);
        }
        if ($closing && get_resource_type($this->stream) === 'stream') {
            stream_bucket_append($out, stream_bucket_new($this->stream, "[end]"));
        }
        return PSFS_PASS_ON;
    }
}

class refusing_filter extends php_user_filter {
    public function onCreate(): bool {
        return false;
    }
}

class feed_filter extends php_user_filter {
    private $held = '';
    public function filter($in, $out, &$consumed, bool $closing): int {
        while ($bucket = stream_bucket_make_writeable($in)) {
            $this->held .= $bucket->data;
            $consumed += $bucket->datalen;
        }
        if (!$closing) return PSFS_FEED_ME;
        stream_bucket_append($out, stream_bucket_new($this->stream, strrev($this->held)));
        return PSFS_PASS_ON;
    }
}

var_dump(stream_filter_register('my.upper', 'upper_filter'));
var_dump(stream_filter_register('my.upper', 'upper_filter'));
var_dump(stream_filter_register('string.rot13', 'upper_filter'));
var_dump(stream_filter_register('trace.*', 'tracing_filter'));
var_dump(stream_filter_register('refuse', 'refusing_filter'));
var_dump(stream_filter_register('feed', 'feed_filter'));
var_dump(in_array('my.upper', stream_get_filters()));

// a read filter on a memory stream
$fp = fopen('php://memory', 'w+');
fwrite($fp, "hello world\nsecond line\n");
rewind($fp);
$f = stream_filter_append($fp, 'my.upper', STREAM_FILTER_READ);
var_dump(get_resource_type($f));
var_dump(fgets($fp));
var_dump(stream_get_contents($fp));
var_dump(stream_filter_remove($f));
var_dump(get_resource_type($f));
fclose($fp);

// a write filter on a file, with params and a wildcard name
$file = tempnam(sys_get_temp_dir(), 'zf');
$fp = fopen($file, 'w');
$t = stream_filter_append($fp, 'trace.one', STREAM_FILTER_WRITE, ['a' => 1]);
fwrite($fp, "abc");
fwrite($fp, "defgh");
fclose($fp);
var_dump(file_get_contents($file));

// prepend runs before the rest of the chain
$fp = fopen($file, 'w');
stream_filter_append($fp, 'string.rot13', STREAM_FILTER_WRITE);
stream_filter_prepend($fp, 'my.upper', STREAM_FILTER_WRITE);
fwrite($fp, "Hello");
fclose($fp);
var_dump(file_get_contents($file));

// onCreate returning false
$fp = fopen('php://memory', 'w+');
var_dump(stream_filter_append($fp, 'refuse'));
var_dump(stream_filter_append($fp, 'no.such.filter'));

// a filter that holds everything until the stream closes
$fp = fopen($file, 'w');
stream_filter_append($fp, 'feed', STREAM_FILTER_WRITE);
fwrite($fp, "12345");
fwrite($fp, "678");
fclose($fp);
var_dump(file_get_contents($file));

// buckets
$fp = fopen('php://memory', 'w+');
$b = stream_bucket_new($fp, 'payload');
var_dump($b instanceof StreamBucket, $b->data, $b->datalen, $b->dataLength, get_resource_type($b->bucket));

// a read filter appended when data is already buffered filters that data
$fp = fopen($file, 'w+');
fwrite($fp, "line one\nline two\n");
rewind($fp);
var_dump(fgets($fp));
stream_filter_append($fp, 'string.toupper');
var_dump(fgets($fp));

unlink($file);
echo "done\n";
