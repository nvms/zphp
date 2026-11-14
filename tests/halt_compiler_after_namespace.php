<?php
// __halt_compiler() may follow bracketed namespaces: it is no code outside them
namespace App {
    echo "inside\n";
    echo strlen(file_get_contents(__FILE__, false, null, __COMPILER_HALT_OFFSET__)), "\n";
}
__halt_compiler();
trailing data { that is not php
