<?php
// a user filter's callback run while php closes the streams left at shutdown
// can't create another user filter: their map is gone by then
class Plain extends php_user_filter {
    public function filter($in, $out, &$consumed, $closing): int {
        while ($bucket = stream_bucket_make_writeable($in)) {
            $consumed += $bucket->datalen;
            stream_bucket_append($out, $bucket);
        }
        return PSFS_PASS_ON;
    }
}
class Outer extends Plain {
    public function filter($in, $out, &$consumed, $closing): int {
        echo "filter, closing: ", var_export($closing, true), "\n";
        $s = fopen('php://memory', 'w+');
        var_dump(stream_filter_append($s, 'plain.user') !== false);
        return parent::filter($in, $out, $consumed, $closing);
    }
}
stream_filter_register('plain.user', Plain::class);
stream_filter_register('outer.user', Outer::class);
$stream = fopen('php://memory', 'w+');
stream_filter_append($stream, 'outer.user', STREAM_FILTER_WRITE);
fwrite($stream, "data");
echo "done\n";
