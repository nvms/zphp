<?php
// disk_free_space and its alias warn under their own names
var_dump(disk_free_space("/zphp_no_such_dir"), diskfreespace("/zphp_no_such_dir"));
var_dump(disk_total_space("/zphp_no_such_dir"));
var_dump(is_float(disk_free_space(sys_get_temp_dir())), disk_total_space(sys_get_temp_dir()) > 0);
foreach (['disk_free_space', 'diskfreespace', 'disk_total_space'] as $fn) {
    try {
        $fn("/tmp\0x");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
