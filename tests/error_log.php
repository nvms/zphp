<?php
// regression: error_log() was an undefined function. WordPress's SQLite
// integration plugin calls it from WP_SQLite_DB::print_error(), so any DB
// query that hit an error fataled with 'Call to undefined function'. type 0
// (and 4) route the message to stderr; type 3 appends to a named file.
// only the stdout-visible return values are checked here - the stderr writes
// are intentionally not captured by the compat harness
var_dump(error_log("system logger message"));
var_dump(error_log("sapi message", 4));

$f = sys_get_temp_dir() . "/zphp_error_log_" . getmypid() . ".txt";
@unlink($f);
var_dump(error_log("first line\n", 3, $f));
var_dump(error_log("second line\n", 3, $f));
echo file_get_contents($f);
@unlink($f);

// bad arg shapes return false
var_dump(error_log(""));
