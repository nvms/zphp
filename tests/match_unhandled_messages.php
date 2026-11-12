<?php
enum Status { case Active; case Archived; }
foreach ([null, true, 1.5, 3.0, 42, 'short', 'a string longer than fifteen bytes', "line\nbreak", [1], new stdClass, Status::Archived] as $value) {
    try {
        echo match ($value) {
            Status::Active, 0, => 'matched',
        }, "\n";
    } catch (UnhandledMatchError $e) {
        echo $e->getMessage(), "\n";
    }
}
echo match (2) {
    1, 2, => 'two',
    default, => 'other',
}, "\n";
