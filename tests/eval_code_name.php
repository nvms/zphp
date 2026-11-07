<?php
// php names evaluated code after where eval ran, and its frame shows no
// arguments
eval('echo basename(__FILE__), " ", __LINE__, "\n";');
function run($code) { eval($code); }
try {
    run('throw new RuntimeException("inside");');
} catch (RuntimeException $e) {
    echo basename($e->getFile()), "\n";
    echo preg_replace('~/\S*/~', '', $e->getTraceAsString()), "\n";
}
