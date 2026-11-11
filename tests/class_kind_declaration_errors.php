<?php
// declarations naming the wrong kind of class: a trait used in an interface,
// a class extending a trait or an interface, implementing a trait or a
// class, and "_" as a name. each runs in its own process (most are fatal)

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'ckd');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('trait T {} interface I { use T; }');
run('trait T {} class C extends T {}');
run('interface I {} class C extends I {}');
run('trait T {} class C implements T {}');
run('class B {} class C implements B {}');
run('trait _ {} echo "declared\n";');
run('class _ {} interface _I {} enum _E {} echo "declared\n";');
run('namespace N; interface _ {} echo "declared\n";');
