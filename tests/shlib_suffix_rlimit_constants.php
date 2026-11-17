<?php
// PHP_SHLIB_SUFFIX names shared modules' extension, and posix's
// POSIX_RLIMIT_* constants name the system's resource limits
var_dump(PHP_SHLIB_SUFFIX);
foreach (get_defined_constants() as $name => $value) {
    if (str_starts_with($name, 'POSIX_RLIMIT_')) echo $name, '=', $value, "\n";
}
if (function_exists('posix_getrlimit')) {
    $limits = posix_getrlimit(POSIX_RLIMIT_NOFILE);
    var_dump(is_array($limits));
}
