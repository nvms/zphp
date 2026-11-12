<?php
// a resource argument in a stack trace prints as its id
ini_set('zend.exception_ignore_args', '0');

function takes($handle, $other) {
    throw new RuntimeException("boom");
}

$fp = fopen('php://memory', 'r');
try {
    takes($fp, STDIN);
} catch (RuntimeException $e) {
    echo preg_replace('/#(\d+) \/\S*: /', '#$1 FILE: ', $e->getTraceAsString()), "\n";
}
fclose($fp);
try {
    takes($fp, 1);
} catch (RuntimeException $e) {
    echo preg_replace('/#(\d+) \/\S*: /', '#$1 FILE: ', $e->getTraceAsString()), "\n";
}
