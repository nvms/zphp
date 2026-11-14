<?php
// compile errors php raises for writes to call results in unset(), for a
// break or continue that leaves a finally block, and for declaring true,
// false or null
$cases = [
    'unset($f());',
    'unset(f());',
    'unset($o->m());',
    'unset(A::m());',
    'function a() { do { try { } finally { break; } } while (0); }',
    'function b() { for (;;) { do { try { } finally { continue 2; } } while (0); } }',
    'function c() { try { } finally { foreach ([1] as $v) { break; } switch (1) { case 1: break; } } }',
    'function d() { while (1) { try { break; } finally { } } }',
    'namespace x; const NULL = 1;',
    'const True = 1;',
    'const nullable = 1;',
];
foreach ($cases as $i => $code) {
    $file = sys_get_temp_dir() . "/zphp-compile-$i-" . getmypid() . ".php";
    file_put_contents($file, "<?php\n$code\necho 'compiled';\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, "\n  ", trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
