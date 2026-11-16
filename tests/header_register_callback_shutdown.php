<?php
// a script that prints nothing sends its headers at the end of the request,
// after the shutdown functions, so one registered there never runs
register_shutdown_function(function () {
    header_register_callback(function () {
        echo "header\n";
        register_shutdown_function(function () { echo "shutdown\n"; });
    });
});
