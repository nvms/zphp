<?php
// strict base64_decode fails on a truncated last group, on padding that
// doesn't complete one, and on data after padding; whitespace is skipped
$inputs = ["", "=", "==", "V", "V=", "VV", "VV=", "VV==", "VV===", "VVV", "VVV=", "VVV==", "VVVV", "VVVV=",
    "UEhQ\n", "UEg=\r\n", "UA==\n", "U A = =", "UA==UA==", "U\x0bA==", "@@@@", "UE*hQ", "\tUEhQ "];
foreach ($inputs as $in) {
    echo json_encode($in), " ", json_encode(base64_decode($in)), " ", json_encode(base64_decode($in, true)), "\n";
}
