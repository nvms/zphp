<?php
// regression: unpack() emits PHP's 'not enough input values' warning when the
// format string consumes more bytes than the input provides, then returns
// false. previously zphp returned false silently. the warning text is what
// log analyzers / test harnesses match on.
$packed = pack('NnC', 100000, 500, 7);   // 7 bytes
unpack('Nbig/Nmed/Csmall', $packed);     // Nmed needs 4, only 3 left
unpack('N', 'ab');                        // needs 4, only 2
unpack('n', 'a');                         // needs 2, only 1
unpack('q', 'short');                     // needs 8, only 5

// suppressed form returns false
var_dump(@unpack('N', 'ab'));

// exact-fit input - no warning
print_r(unpack('Cval', 'x'));
print_r(unpack('npair', pack('n', 4096)));

// a partial multi-field unpack that fits exactly still works
print_r(unpack('Cfirst/Csecond', 'AB'));
