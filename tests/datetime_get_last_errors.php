<?php
// regression: DateTime::getLastErrors returns the structured array
// (warning_count, warnings, error_count, errors) on parse failure and
// false when the most recent parse succeeded (PHP 8.2+ behavior)

// successful parse: getLastErrors returns false
DateTime::createFromFormat("Y-m-d", "2024-03-15");
var_dump(DateTime::getLastErrors());

// failed parse: getLastErrors returns the array
DateTime::createFromFormat("Y-m-d", "not a date");
$err = DateTime::getLastErrors();
echo gettype($err) . "\n";
echo "ec=" . $err['error_count'] . " wc=" . $err['warning_count'] . "\n";
echo "errors-count=" . count($err['errors']) . " warnings-count=" . count($err['warnings']) . "\n";
echo "has-errors-array: " . (is_array($err['errors']) ? 'y' : 'n') . "\n";

// successful parse afterwards resets to false
DateTime::createFromFormat("Y-m-d", "2024-12-31");
var_dump(DateTime::getLastErrors());

// DateTimeImmutable shares the same static state
DateTimeImmutable::createFromFormat("Y-m-d", "garbage");
$err = DateTimeImmutable::getLastErrors();
echo "dti ec=" . $err['error_count'] . "\n";
