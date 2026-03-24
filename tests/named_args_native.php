<?php

// named arguments for native/stdlib functions

echo substr(string: "hello world", offset: 6) . "\n";
echo substr(offset: 0, string: "hello", length: 3) . "\n";

echo in_array(needle: "b", haystack: ["a", "b", "c"]) ? "found" : "missing";
echo "\n";

echo str_replace(search: "X", replace: "Y", subject: "aXbXc") . "\n";

echo implode(separator: "-", array: [1, 2, 3]) . "\n";

echo round(num: 3.14159, precision: 2) . "\n";

echo str_pad(string: "hi", length: 5, pad_string: ".") . "\n";

echo json_encode(value: ["a" => 1]) . "\n";
