<?php
// code php's grammar rejects: a static property or parameter type, `$`
// before anything but a variable, `{` or `$`, const below the top level, and
// `<?=` where an identifier goes

$cases = [
    "<?php\nclass Test {\n    public ?static \$foo;\n}\necho 'ran';\n",
    "<?php\nclass Test {\n    public int|static \$foo;\n}\necho 'ran';\n",
    "<?php\nfunction f(?static \$x) {}\necho 'ran';\n",
    "<?php\n\$\"name\";\necho 'ran';\n",
    "<?php\n\$x = \$'a';\necho 'ran';\n",
    "<?php\nfunction x() {\n    const X = 1;\n}\necho 'ran';\n",
    "<?php\nfunction x() {\n    #[Attr] const X = 1;\n}\necho 'ran';\n",
    "<?php\nif (true) {\n    const X = 1;\n}\necho 'ran';\n",
    "<?php\ntrait T { public function x() {} }\nclass C {\n    use T {\n        x as y?><?= as my_echo;\n    }\n}\n",
    // still accepted
    "<?php\nnamespace A { const X = 1; #[Attr] const Y = 2; echo X, Y, \"\\n\"; }\nnamespace { \$a = 'b'; \$b = 'c'; echo \$\$a, \${'a'}, \"\\n\"; }\n",
    "<?php\nclass D { public static ?D \$p = null; public function m(): static { return \$this; } }\necho get_class((new D)->m()), \"\\n\";\n",
];

$file = sys_get_temp_dir() . '/zphp_grammar_rejects_' . getmypid() . '.php';
foreach ($cases as $code) {
    file_put_contents($file, $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out), "\n";
}
unlink($file);
