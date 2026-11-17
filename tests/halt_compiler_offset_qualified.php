<?php
// __COMPILER_HALT_OFFSET__ written unqualified or fully qualified is the
// offset in any namespace; namespace\ names a constant of that namespace
namespace {
    var_dump(__COMPILER_HALT_OFFSET__ === \__COMPILER_HALT_OFFSET__);
    echo substr(file_get_contents(__FILE__), \__COMPILER_HALT_OFFSET__);
}
namespace Data {
    var_dump(__COMPILER_HALT_OFFSET__ === \__COMPILER_HALT_OFFSET__);
    try {
        echo namespace\__COMPILER_HALT_OFFSET__;
    } catch (\Error $e) {
        echo $e->getMessage(), "\n";
    }
}
__halt_compiler();payload after the halt
