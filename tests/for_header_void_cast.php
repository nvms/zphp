<?php
// a for header's expressions are lists: each value but the condition's last
// is thrown away, so (void) may discard it and #[\NoDiscard] warns when it
// isn't

set_error_handler(function ($errno, $message) {
    echo "warning: $message\n";
    return true;
});

$count = 0;

#[NoDiscard]
function bump() {
    global $count;
    $count++;
    return $count;
}

for ($count = 0, (void) bump(), bump(); (void) bump(), bump() < 20; bump(), $count++, bump(), (void) bump()) {
    echo $count, "\n";
}

// a condition list's earlier values are dropped and the last one tested
$i = 0;
for (; print("check "), $i < 3; $i++) {
    echo $i, "\n";
}

$log = [];
for ($a = 1, $b = 10; $log[] = $a, $a < $b; $a *= 2, $b--) {}
echo implode(',', $log), "\n";
