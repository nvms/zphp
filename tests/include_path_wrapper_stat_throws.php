<?php
// an exception a stream wrapper's url_stat throws while an include searches
// the include_path ends the include, with nothing else reported

class StreamWrapper {
    public $context;
    public function url_stat($path, $flags) {
        throw new Exception('stat failed');
    }
}

stream_wrapper_register('test', StreamWrapper::class);
set_include_path('test://foo:test://bar');

try {
    require_once 'doesnt_exist.php';
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
try {
    require 'doesnt_exist.php';
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
try {
    include_once 'doesnt_exist.php';
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
try {
    include 'doesnt_exist.php';
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

try {
    var_dump(stream_resolve_include_path("doesnt_exist.php"));
} catch (Throwable $e) {
    echo $e::class, ": ", $e->getMessage(), "\n";
}
echo "done\n";
