<?php
// memory_limit checks an array's table at the size php allocates for it
// (16 bytes per element packed, 32 per bucket plus the hash otherwise), and
// the exhaustion names that size
ini_set('memory_limit', '6M');

register_shutdown_function(function () {
    echo error_get_last()['message'], "\n";
});

$packed = [];
for ($i = 0; $i < 100000; $i++) $packed[] = $i;
echo count($packed), " packed\n";
$hash = [];
for ($i = 0; $i < 30000; $i++) $hash["k$i"] = $i;
echo count($hash), " hashed\n";
$more = [];
for ($i = 0; $i < 400000; $i++) $more[] = $i;
echo "not reached\n";
