<?php
// directives php checks as not empty refuse an empty value, and
// arg_separator.input can't change at run time
var_dump(ini_set("arg_separator.output", ""));
var_dump(ini_get("arg_separator.output"));
var_dump(ini_set("arg_separator.output", ";"));
var_dump(ini_get("arg_separator.output"));
var_dump(ini_set("arg_separator.input", ";"));
var_dump(ini_get("arg_separator.input"));
$before = ini_get("include_path");
var_dump(ini_set("include_path", ""));
var_dump(ini_get("include_path") === $before);
