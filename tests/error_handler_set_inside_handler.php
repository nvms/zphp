<?php
// set_error_handler inside a running handler pushes "no handler" (php takes
// the running one off while it runs), so restoring brings that back and the
// running handler stays installed afterwards
set_error_handler(function () { echo "first\n"; });
set_error_handler(function () {
    echo "second\n";
    set_error_handler(function () { echo "inner\n"; });
    $undefinedInside++;
    restore_error_handler();
});
$a++;
$b++;
restore_error_handler();
$c++;
restore_error_handler();
var_dump(set_error_handler(null));
var_dump(restore_error_handler());
var_dump(set_error_handler('strlen'), set_error_handler(null), restore_error_handler(), set_error_handler(null));
