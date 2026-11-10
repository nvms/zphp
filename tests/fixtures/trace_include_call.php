<?php

function takes_int_in_include(int $x) { return $x; }

takes_int_in_include(1.5e300);
