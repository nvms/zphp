<?php
ini_set("memory_limit", "512M");
$after_set = ini_get("memory_limit");
ini_restore("memory_limit");
echo $after_set, "|", ini_get("memory_limit"), "\n";
