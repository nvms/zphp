<?php
// a fatal error is followed by the stack it happened on, at the line it
// happened, unless fatal_error_backtraces is off (see
// fatal_error_trace_off.php)
function spin() {
    set_time_limit(1);
    while (true);
}
spin();
