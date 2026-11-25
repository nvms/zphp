<?php
// openlog()'s prefix and proc_open()'s cwd are paths: a NUL byte is a ValueError
try {
    openlog("foo\0bar", LOG_NDELAY, LOG_USER);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(openlog("zphp-test", LOG_NDELAY, LOG_USER));
closelog();
try {
    proc_open("does_not_matter", [], $pipes, "foo\0bar");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    proc_open([], [], $pipes, "foo\0bar");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
