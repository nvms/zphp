<?php
// ini_get_all lists one extension's directives sorted by name, with their
// values or details, and refuses an extension that isn't loaded
set_error_handler(function ($no, $msg) { echo $msg, "\n"; });
var_dump(gettype(ini_get_all()));
var_dump(ini_get_all(""));
var_dump(ini_get_all("nosuchextension"));
var_dump(ini_get_all("reflection"));
var_dump(ini_get_all("pcre", false));
ini_set('pcre.backtrack_limit', '5000');
var_dump(ini_get_all("pcre"));
var_dump(ini_get_all("PCRE"));
var_dump(ini_get_all("", ""));
