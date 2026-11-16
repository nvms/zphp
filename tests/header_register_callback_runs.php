<?php
// header_register_callback's callback runs as the headers are sent: before
// the first output that reaches the top level, its own output first
header_register_callback(function () {
    echo "[headers]";
});
ob_start();
echo "buffered\n";
ob_end_clean();
var_dump(headers_sent());
echo "first\n";
echo "second\n";
// a callback registered once the headers went out never runs
var_dump(header_register_callback(function () { echo "never\n"; }));
