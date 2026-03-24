<?php

// basic parse_str - note: in PHP 8, parse_str requires a second arg (the result array)
// zphp returns the array directly since we don't have reference params for this
$result = parse_str("name=John&age=30&city=NYC");
echo $result["name"] . "\n";
echo $result["age"] . "\n";
echo $result["city"] . "\n";

// URL-encoded values
$result2 = parse_str("greeting=hello+world&path=%2Fsome%2Fpath");
echo $result2["greeting"] . "\n";
echo $result2["path"] . "\n";

// key without value
$result3 = parse_str("flag&key=val");
echo $result3["flag"] . "\n";
echo $result3["key"] . "\n";

// empty value
$result4 = parse_str("empty=&full=yes");
echo $result4["empty"] . "\n";
echo $result4["full"] . "\n";
