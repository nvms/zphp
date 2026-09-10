<?php
echo json_encode([
    "loaded" => php_ini_loaded_file() !== false,
    "tz" => ini_get("date.timezone"),
    "tz_default" => date_default_timezone_get(),
    "tz_date" => date("e"),
    "error_reporting" => ini_get("error_reporting"),
    "error_reporting_live" => error_reporting(),
    "display_errors" => ini_get("display_errors"),
    "memory_limit" => ini_get("memory_limit"),
    "max_execution_time" => ini_get("max_execution_time"),
    "name" => ini_get("app.name"),
    "flag" => ini_get("app.flag"),
    "quoted" => ini_get("app.quoted"),
    "missing" => ini_get("app.missing"),
]), "\n";
