<?php
// the procedural date_get_last_errors() is registered and reports
// the same parse-error state as DateTime::getLastErrors()

var_dump(function_exists('date_get_last_errors'));

// succesful parse
DateTime::createFromFormat("Y-m-d", "2024-03-15");
var_dump(date_get_last_errors());
var_dump(date_get_last_errors() === DateTime::getLastErrors());

// failed parse
DateTime::createFromFormat("Y-m-d", "not a date");
$err = date_get_last_errors();
echo gettype($err) . "\n";
var_dump($err === DateTime::getLastErrors());
echo "ec=" . $err['error_count'] . " wc=" . $err['warning_count'] . "\n";
echo "has-errors-array: " . (is_array($err['errors']) ? 'y' : 'n') . "\n";
echo "has-warnings-array: " . (is_array($err['warnings']) ? 'y' : 'n') . "\n";

// a later successful parse resets both to false
DateTime::createFromFormat("Y-m-d", "2024-12-31");
var_dump(date_get_last_errors());

// DateTimeImmutable shares the same state as the procedural function
DateTimeImmutable::createFromFormat("Y-m-d", "garbage");
var_dump(date_get_last_errors() === DateTimeImmutable::getLastErrors());
