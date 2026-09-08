<?php
function defineOwnedStrings(): void {
    define('OWNED_' . 'VALUE', 'constant-' . 42);
    define('OWNED_' . 'ARRAY', ['nested-' . 7]);
}
defineOwnedStrings();
gc_collect_cycles();
for ($i = 0; $i < 100; ++$i) $temporary = 'overwrite-' . $i;
var_dump(OWNED_VALUE, OWNED_ARRAY, constant('OWNED_' . 'VALUE'));
