<?php
// mb_internal_encoding follows the ini settings until it is set
var_dump(mb_internal_encoding());
ini_set("default_charset", "iso-8859-1");
var_dump(mb_internal_encoding());
ini_set("internal_encoding", "cp1252");
var_dump(mb_internal_encoding());
ini_set("internal_encoding", "nonsense");
var_dump(mb_internal_encoding());
var_dump(mb_internal_encoding("shift_jis"), mb_internal_encoding());
ini_set("internal_encoding", "UTF-8");
var_dump(mb_internal_encoding());
var_dump(mb_internal_encoding("UNICODE"), mb_internal_encoding());
try { mb_internal_encoding("nope"); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
