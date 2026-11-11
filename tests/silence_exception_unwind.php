<?php
// an exception leaving an @ expression restores error_reporting, as php's
// live silence ranges do

error_reporting(E_ALL);

function takes($arg) {
}
function throws() {
    throw new Exception("test");
}

try {
    @takes(@throws());
} catch (Exception $e) {
}
var_dump(error_reporting());

function nested() {
    return @throws();
}
try {
    @nested();
} catch (Exception $e) {
    var_dump(error_reporting());
}
var_dump(error_reporting());

try {
    @(function () {
        try {
            @throws();
        } catch (Exception $e) {
            var_dump(error_reporting());
        }
    })();
} catch (Exception $e) {
}
var_dump(error_reporting());
