<?php
// a null callback for array_filter keeps the truthy elements, as no callback does
var_dump(array_filter([1, 0, 2, null, "a"], null));
var_dump(array_filter(["a" => 0, "b" => 1], null, ARRAY_FILTER_USE_KEY));
var_dump(set_error_handler(null), set_exception_handler(null));
var_dump(array_map(null, [1, 2]));
