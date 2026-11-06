<?php
// after an empty match in utf mode the next attempt starts one character on
$s = "a" . str_repeat("\u{1f612}", 3) . "é";
var_dump(preg_replace("//u", "-", $s), preg_replace("//u", "-", $s, 2), preg_replace_callback("//u", fn() => "+", $s));
var_dump(preg_match_all("//u", $s), preg_replace(["//u", "/a/"], ["-", "b"], $s), preg_replace_callback_array(["//u" => fn() => "|"], $s), preg_split("//u", $s));
