<?php
// regression: date_parse_from_format() actually drives parsing by the format
// string instead of delegating to date_parse() and losing the format. supports
// Y/y/m/n/d/j/H/G/h/g/i/s/u/v/a/A/D/l/M/F/!/| plus literal punctuation.
// PHP convention: when any time component is parsed, the rest default to 0;
// when only date is parsed, time fields stay false. fraction stays false if
// no time field touched
print_r(date_parse_from_format("d/m/Y", "15/03/2024"));
print_r(date_parse_from_format("Y-m-d H:i:s", "2024-03-15 10:30:45"));
print_r(date_parse_from_format("!d-M-y", "01-Jan-23"));
print_r(date_parse_from_format("h:i A", "11:30 PM"));
print_r(date_parse_from_format("d/m/Y H:i:s.u", "15/03/2024 10:30:45.123456"));
print_r(date_parse_from_format("Y", "2024"));
print_r(date_parse_from_format("H", "10"));
