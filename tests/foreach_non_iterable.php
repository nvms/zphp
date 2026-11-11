<?php
// foreach over anything but an array or object skips the loop with php's
// warning, which names the value's type
set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});
foreach ([true, false, null, 1, 1.5, "text"] as $value) {
    foreach ($value as $k => $v) {
        echo "never\n";
    }
}
function inside() {
    foreach ($undefined as $v) {
    }
    foreach ((function () { return 3; })() as $v) {
    }
}
inside();
$s = "abc";
foreach ($s as &$byRef) {
}
echo "done\n";
