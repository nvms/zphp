<?php
echo json_encode(null);
echo "\n";
echo json_encode(true);
echo "\n";
echo json_encode(42);
echo "\n";
echo json_encode("hello");
echo "\n";
echo json_encode([1, 2, 3]);
echo "\n";
echo json_encode(['name' => 'PHP', 'version' => 8]);
echo "\n";

$decoded = json_decode('[1,2,3]');
echo count($decoded);
echo "\n";
echo $decoded[1];
echo "\n";

$obj = json_decode('{"name":"zphp","version":1}');
echo $obj['name'];
echo "\n";
echo $obj['version'];
echo "\n";

echo json_encode(json_decode('{"a":true,"b":false,"c":null}'));
echo "\n";
