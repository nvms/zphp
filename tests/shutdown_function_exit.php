<?php
// exit() in a shutdown function ends the shutdown functions with its status
register_shutdown_function(function () { echo "one\n"; exit(3); });
register_shutdown_function(function () { echo "two\n"; });
echo "end\n";
