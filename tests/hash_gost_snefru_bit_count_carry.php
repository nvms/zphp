<?php
// gost and snefru keep the message length in bits as two 32-bit words; a
// carry into the high word (past 512 MiB of input) adds exactly, which
// earlier versions got one bit short. a context restored with a count near
// the boundary shows it without hashing that much
function near_boundary(string $algo, int $low_index, int $high_index, int $low, int $high = 0): HashContext {
    $ctx = hash_init($algo);
    hash_update($ctx, 'seed');
    $data = $ctx->__serialize();
    $data[2][$low_index] = $low;
    $data[2][$high_index] = $high;
    $array = serialize($data);
    return unserialize('O:11:"HashContext":' . substr($array, 2));
}

foreach ([['gost', 16, 17], ['gost-crypto', 16, 17], ['snefru', 17, 16], ['snefru256', 17, 16]] as [$algo, $low, $high]) {
    foreach ([[0xFFFFFFF0, 0, 'x'], [0xFFFFFFF0, 0, str_repeat('y', 40)], [0xFFFFFFFF, 0, 'z'], [0xFFFFFF00, 1, str_repeat('w', 100)], [0x7FFFFFF8, 0, 'v']] as [$count, $hi, $more]) {
        $ctx = near_boundary($algo, $low, $high, $count, $hi);
        hash_update($ctx, $more);
        $copy = hash_copy($ctx);
        echo $algo, ' ', dechex($count), ' +', strlen($more), ': ', hash_final($ctx), "\n";
        $state = $copy->__serialize()[2];
        echo '  count words: ', $state[$high], ' ', $state[$low], "\n";
    }
}
