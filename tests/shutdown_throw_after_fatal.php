<?php
// a fatal error's bailout ends with its report: what a shutdown function
// throws afterwards is an uncaught exception of its own
register_shutdown_function(static function (): void {
    echo "shutdown\n";
    throw new Exception("from shutdown");
});
echo "start\n";
var_dump(new class { public function __debugInfo() { return ''; } });
