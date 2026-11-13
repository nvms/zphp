<?php
// a function or a global constant is named by an identifier, never by a
// keyword (class constants and methods may use most keywords)

foreach ([
    'function exit() {}', 'function die() {}', 'function list() {}', 'function readonly() { return 1; } echo readonly(), "\n";',
    'function enum() { return 2; } echo enum(), "\n";', 'function NULL() { return 7; } echo "declared\n";', 'function false() {} function true() {}', 'const exit = 1;', 'const die = 1;', 'const readonly = 1;',
    'const enum = 3; echo enum, "\n";', 'class K { const exit = 4; const list = 5; } echo K::exit, K::list, "\n";',
    'class M { function exit() { return 6; } } echo (new M)->exit(), "\n";', 'namespace N; function die() {}', 'namespace N; const exit = 1;',
] as $code) {
    $file = tempnam(sys_get_temp_dir(), 'kw');
    file_put_contents($file, "<?php\n$code\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, "\n  ", trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
