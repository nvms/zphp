<?php
// an uncaught exception from a shutdown function, with no exception handler,
// is php's fatal error: it is reported and the remaining ones don't run
register_shutdown_function(function () { echo "one\n"; throw new Exception("boom"); });
register_shutdown_function(function () { echo "two\n"; });
echo "end\n";
