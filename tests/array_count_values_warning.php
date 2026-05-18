<?php
// regression: array_count_values emits a Warning per entry that isn't an
// int or string ('Can only count string and integer values, entry
// skipped'). previously zphp silently skipped non-countable entries
print_r(array_count_values([1, [1, 2], 2, 'a', new stdClass(), 3.14, 1]));

// no warning when all values are countable
print_r(array_count_values([1, 'a', 2, 'b', 1, 'a']));
