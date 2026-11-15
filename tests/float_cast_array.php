<?php
// zval_get_double: an array is 1.0 unless it is empty
var_dump((float) [], (float) [0], (float) [1, 2, 3], (double) ['a' => null]);
var_dump(floatval([]), floatval([5]));
