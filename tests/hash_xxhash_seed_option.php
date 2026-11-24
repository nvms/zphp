<?php
// xxh32 and xxh64 warn about a non-int seed only when a seed is given;
// options without one hash with seed 0 quietly
set_error_handler(function ($no, $msg) {
    echo "error $no: $msg\n";
    return true;
});

foreach (['xxh32', 'xxh64'] as $algo) {
    echo "$algo\n";
    var_dump(hash($algo, 'abc') === hash($algo, 'abc', false, []));
    var_dump(hash($algo, 'abc') === hash($algo, 'abc', false, ['other' => 5]));
    var_dump(hash($algo, 'abc') === hash($algo, 'abc', false, ['seed' => '5']));
    var_dump(hash($algo, 'abc') === hash($algo, 'abc', false, ['seed' => 0]));
    var_dump(hash($algo, 'abc', false, ['seed' => 7]));
    $ctx = hash_init($algo, 0, '', ['secret' => 'ignored']);
    hash_update($ctx, 'abc');
    var_dump(hash_final($ctx) === hash($algo, 'abc'));
}
