<?php
// an abstract method in a class that isn't abstract is a compile error at
// the method's line, before any of the script runs
$file = sys_get_temp_dir() . '/zphp_abstract_' . getmypid() . '.php';
$base = escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d log_errors=0 -d fatal_error_backtraces=0 ';
foreach ([
    "<?php\necho 'ran', PHP_EOL;\nclass Concrete {\n    function ok() {}\n    abstract function f();\n}\n",
    "<?php\necho 'ran', PHP_EOL;\n\$c = new class {\n\n    abstract public function g();\n};\n",
    "<?php\nabstract class Fine { abstract function h(); }\ntrait T { abstract function i(); }\necho 'fine', PHP_EOL;\n",
] as $code) {
    file_put_contents($file, $code);
    $out = [];
    exec($base . escapeshellarg($file) . ' 2>&1', $out, $status);
    $text = str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', trim(implode("\n", $out)));
    echo $text, " (", $status, ")\n";
}
unlink($file);
