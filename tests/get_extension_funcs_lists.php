<?php
// get_extension_funcs() lists an extension's functions, and is false for
// one that isn't loaded
$std = get_extension_funcs("standard");
var_dump(is_array($std), in_array("cos", $std), in_array("strlen", $std), in_array("var_dump", $std));
var_dump(in_array("json_encode", get_extension_funcs("json")), in_array("preg_match", get_extension_funcs("pcre")));
var_dump(get_extension_funcs("no_such_extension"), get_extension_funcs("STANDARD") == $std);
