<?php
// mb_split closes a piece only at a match that ends past the search position
var_dump(mb_split("", "añb"), mb_split(",", "a,b,,c"), mb_split(",", "a,b,c", 2), mb_split("\s*", "a b"), mb_split("x", ""), mb_split(",", ",a,"), mb_split("ñ", "añbñ"), mb_split("b*", "abba"));
