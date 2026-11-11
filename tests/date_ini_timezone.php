<?php
// date.timezone takes only ids from php's database; ini_set() refuses
// anything else, and the ini value is the default zone until a script sets one

var_dump(ini_set("date.timezone", "dummy"));
var_dump(ini_get("date.timezone"));
var_dump(ini_set("date.timezone", "America/New_York"));
echo date_default_timezone_get(), " ", date("Y-m-d H:i:s T", 2377224000), "\n";
var_dump(ini_set("date.timezone", "Mars/Valles_Marineris"));
var_dump(ini_set("date.timezone", "+05:00"));
var_dump(ini_set("date.timezone", "asia/calcutta"));
echo date_default_timezone_get(), "\n";
date_default_timezone_set("Europe/Oslo");
var_dump(ini_set("date.timezone", "Asia/Tokyo"));
echo date_default_timezone_get(), " ", ini_get("date.timezone"), "\n";
var_dump(@date_default_timezone_set("Not/AZone"));
