<?php
// a descriptor given as a resource must be an open stream
$context = stream_context_create();
try {
    proc_open('true', [0 => $context], $pipes);
    echo "not reached\n";
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$fp = fopen("php://memory", "r");
fclose($fp);
try {
    proc_open('true', [1 => $fp], $pipes);
    echo "not reached\n";
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
