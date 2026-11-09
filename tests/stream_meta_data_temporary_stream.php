<?php
// the metadata of a stream that is released right after the call keeps its
// strings
$meta = stream_get_meta_data(fopen(__FILE__, "r"));
var_dump($meta['uri'] === __FILE__, $meta['mode'], $meta['wrapper_type'], $meta['stream_type']);
$meta = stream_get_meta_data(fopen("php://memory", "r+"));
var_dump($meta['uri'], $meta['mode'], $meta['wrapper_type'], $meta['stream_type']);
