<?php
// ReflectionConstant::getFileName() names the file a script's constant was
// defined in (by define() or const), and is false for php's own

namespace Space {
    const SPACED = 1;
}

namespace {
    $inc = sys_get_temp_dir() . '/zphp_const_file_' . getmypid() . '.php';
    file_put_contents($inc, "<?php\ndefine('INCLUDED_DEFINED', 1);\nconst INCLUDED_AST = 2;\n");
    include $inc;
    unlink($inc);

    define('HERE_DEFINED', 42);
    const HERE_AST = 123;
    eval('define("EVAL_DEFINED", 1); const EVAL_AST = 2;');

    $show = function ($file) use ($inc) {
        if ($file === false) return 'false';
        return str_replace([__FILE__, $inc, str_replace('/', DIRECTORY_SEPARATOR, $inc)], ['THIS', 'INC', 'INC'], $file);
    };
    foreach (['PHP_VERSION', 'STDIN', 'E_ALL', 'HERE_DEFINED', 'HERE_AST', 'INCLUDED_DEFINED', 'INCLUDED_AST', 'EVAL_DEFINED', 'EVAL_AST', 'Space\SPACED'] as $name) {
        echo $name, ': ', $show((new ReflectionConstant($name))->getFileName()), "\n";
    }
}
