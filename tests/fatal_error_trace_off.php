<?php
// fatal_error_backtraces off leaves a fatal error with no stack trace
ini_set('fatal_error_backtraces', '0');
function spin() {
    set_time_limit(1);
    while (true);
}
spin();
