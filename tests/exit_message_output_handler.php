<?php
// exit()'s message is written through the output handlers; one that
// throws makes exit() return with the exception
ob_start(function ($text) {
    fwrite(STDOUT, "Handler: " . $text);
    throw new Exception('from handler');
}, chunk_size: 10);
try {
    exit("Hello world!\n");
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
echo "after exit\n";
ob_end_flush();

ob_start(fn ($t) => "<" . $t . ">", 4);
exit("bye\n");
