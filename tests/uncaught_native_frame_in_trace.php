<?php
// regression: uncaught exception originating from a native function shows
// the native at depth 0 in the stack trace, including its args. previously
// zphp's writeStackTrace skipped natives entirely (only user-defined frames
// appeared) so '#0 random_bytes(-1)' was missing
function deepCall() {
    random_bytes(-1);   // throws ValueError
}
deepCall();
