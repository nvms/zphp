<?php
// request_parse_body checks its options, then needs a request with a
// content type, which the cli never has

function attempt(array $options) {
    try {
        request_parse_body($options);
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

attempt([]);
attempt(['post_max_size' => '1M', 'MAX_INPUT_VARS' => 10]);
attempt(['upload_max_filesize' => '1GB']);
attempt(['max_file_uploads' => 'abc']);
attempt(['foo' => 1]);
attempt([42 => 1]);
attempt(['' => 1]);
attempt(['max_input_vars' => []]);
attempt(['max_input_vars' => 1.5]);
var_dump(new RequestParseBodyException('x') instanceof Exception);
