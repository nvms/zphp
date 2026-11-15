<?php
// zend.max_allowed_stack_size sets how deep natives may recurse: serialize,
// json_encode, http_build_query and var_dump stop on very deep data the way
// php's stack checks do

$child = <<<'PHP'
<?php
class Node { public $next; }
$first = new Node();
$node = $first;
for ($i = 0; $i < 50000; $i++) {
    $node->next = new Node();
    $node = $node->next;
}
try {
    serialize($first);
} catch (Error $e) {
    echo preg_replace('/\d+ bytes/', 'N bytes', $e->getMessage()), "\n";
}
var_dump(json_encode($first), json_last_error_msg());

$q = null;
for ($i = 0; $i < 5000; $i++) {
    $q = [$i => $q];
}
try {
    http_build_query($q, 'p');
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

ob_start();
var_dump($first);
$dump = ob_get_clean();
var_dump(str_contains($dump, 'nesting level too deep'));

var_dump(ini_get('zend.max_allowed_stack_size'));
while ($next = $first->next) {
    $first->next = $next->next;
}
echo "done\n";
PHP;

$file = tempnam(sys_get_temp_dir(), 'stk');
file_put_contents($file, $child);
$php = escapeshellarg(PHP_BINARY);
echo shell_exec("$php -n -d zend.max_allowed_stack_size=512K " . escapeshellarg($file));
// the default detects the real stack: the same data is fine
$small = '<?php $a = []; for ($i = 0; $i < 200; $i++) { $a = [$a]; } echo strlen(serialize($a)), " ", var_export(ini_get("zend.max_allowed_stack_size"), true), "\n";';
file_put_contents($file, $small);
echo shell_exec("$php -n " . escapeshellarg($file));
unlink($file);
