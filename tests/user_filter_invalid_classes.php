<?php
// a user filter's filtername and params are written as from outside the
// class (visibility, types and the dynamic property rules apply, a second
// error chaining the first), a filter() that can't be called is an Error
// after the unprocessed buckets warning, and a non-int result converts with
// a warning
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });

class NoFilter {}
class PrivateName { private $filtername; }
class TypedName { public array $filtername; }
class PrivateFilter {
    public $filtername;
    public $params;
    private function filter($in, $out, &$consumed, bool $closing): int { return PSFS_PASS_ON; }
}
class ObjectResult {
    public $filtername;
    public $params;
    public function filter($in, $out, &$consumed, bool $closing) { return new stdClass(); }
}

foreach (['NoFilter', 'PrivateName', 'TypedName', 'SensitiveParameter', 'PrivateFilter', 'ObjectResult'] as $i => $class) {
    echo "-- $class\n";
    stream_filter_register("f$i", $class);
    $fp = fopen("php://memory", "w");
    try {
        var_dump(is_resource(stream_filter_append($fp, "f$i")));
    } catch (Throwable $e) {
        do {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        } while ($e = $e->getPrevious());
    }
    try {
        var_dump(fwrite($fp, "Hello\n"));
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    try {
        fclose($fp);
    } catch (Throwable $e) {
        echo "on close: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    $o = new SensitiveParameter();
    $o->x = 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
