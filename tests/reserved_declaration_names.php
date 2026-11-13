<?php
// self and parent are names to php's grammar: declaring a class-like with
// one, or importing under one, is refused as reserved rather than a syntax
// error; the other reserved names are refused for every kind of declaration

$cases = [
    'class self {}', 'abstract class parent {}', 'trait self {}', 'interface parent {}', 'enum self {}',
    'enum parent: string {}', 'interface Int {}', 'trait Mixed {}', 'use Foo\Bar as self;',
    'use Foo\Bar as parent;', 'use Foo\{A as self};', 'use Foo\self;', 'class selfish {} echo "ok";',
];
foreach ($cases as $code) {
    try {
        eval($code);
        echo "\n";
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    $file = tempnam(sys_get_temp_dir(), 'rdn');
    file_put_contents($file, "<?php\n$code\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, ' => ', trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
