<?php
// the $exclude_disabled argument is deprecated and changes nothing
$all = get_defined_functions();
$again = get_defined_functions(false);
var_dump(count($all['internal']) === count($again['internal']));
var_dump(isset(get_defined_functions(true)['user']));
