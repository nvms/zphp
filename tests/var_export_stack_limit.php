<?php
// var_export checks the native stack on every value it exports, so very deep
// arrays and objects end in php's stack-size Error instead of a crash, and
// nothing is printed or returned

$child = <<<'PHP'
<?php
function attempt(string $name, mixed $value, bool $return): void {
    ob_start();
    try {
        $r = var_export($value, $return);
        $printed = ob_get_clean();
        echo "$name: not stopped (", strlen($printed) + strlen((string) $r), " bytes)\n";
    } catch (Error $e) {
        $printed = ob_get_clean();
        echo "$name: ", get_class($e), ": ", preg_replace('/\d+ bytes/', 'N bytes', $e->getMessage()), "\n";
        echo "  printed: ", strlen($printed), "\n";
    }
}

$data = 0;
for ($i = 0; $i < 50000; $i++) {
    $data = [$data];
}
attempt('array', $data, true);
attempt('array, printed', $data, false);
while (is_array($data)) {
    $data = $data[0];
}

class StackNode { public ?StackNode $next = null; }
$first = new StackNode();
$node = $first;
for ($i = 0; $i < 50000; $i++) {
    $node->next = new StackNode();
    $node = $node->next;
}
attempt('object', $first, true);
$node = $first;
while ($node !== null) {
    $next = $node->next;
    $node->next = null;
    $node = $next;
}
PHP;

$file = tempnam(sys_get_temp_dir(), 'vex');
file_put_contents($file, $child);
$php = escapeshellarg(PHP_BINARY);
echo shell_exec("$php -n -d zend.max_allowed_stack_size=512K " . escapeshellarg($file));
unlink($file);

// with the detected stack, shallow data exports as before
class StackNode { public ?StackNode $next = null; }
$o = new StackNode();
$o->next = new StackNode();
var_export([$o, [1, [2]]]);
echo "\n";
