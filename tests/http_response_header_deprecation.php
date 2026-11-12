<?php
// reading the predefined $http_response_header is deprecated (php 8.5),
// at compile time, until the code assigns it itself
var_dump(isset($http_response_header));
var_dump($http_response_header ?? 'none');
echo @$http_response_header, "\n";
$http_response_header = ['assigned'];
var_dump($http_response_header);
