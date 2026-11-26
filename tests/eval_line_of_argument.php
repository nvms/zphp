<?php
// eval() is on the line of its argument, a heredoc's being its body's
function where() {
    $t = debug_backtrace();
    echo $t[0]['file'] === __FILE__ ? 'main' : basename($t[0]['file']), ':', $t[0]['line'], ' ', $t[1]['line'] ?? '-', "\n";
}
eval(<<<'EOT'
where();
EOT);
eval(
    'where();'
);
$x = 'where();';
eval(
    <<<EOT
    $x
    EOT
);
eval('where();');
eval(<<<EOT
where();
EOT
);
try {
    eval(
        'throw new Exception("e");'
    );
} catch (Exception $e) {
    echo basename($e->getFile()), ' ', $e->getLine(), "\n";
}
