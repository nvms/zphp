<?php
// ini_get() and ini_get_all() report php's built-in defaults for directives
// nothing has set

$names = [
    'allow_url_fopen', 'auto_globals_jit', 'default_socket_timeout', 'enable_post_data_reading',
    'error_log_mode', 'expose_php', 'file_uploads', 'filter.default', 'hard_timeout',
    'highlight.comment', 'highlight.default', 'highlight.html', 'highlight.keyword', 'highlight.string',
    'implicit_flush', 'max_input_nesting_level', 'max_input_vars', 'max_multipart_body_parts',
    'mbstring.encoding_translation', 'mbstring.http_output_conv_mimetypes', 'mbstring.language',
    'mbstring.regex_retry_limit', 'mbstring.regex_stack_limit', 'mbstring.strict_detection',
    'output_buffering', 'phar.readonly', 'phar.require_hash', 'realpath_cache_size', 'realpath_cache_ttl',
    'report_zend_debug', 'session.auto_start', 'session.cache_expire', 'session.cache_limiter',
    'session.cookie_path', 'session.lazy_write', 'session.serialize_handler',
    'session.sid_bits_per_character', 'session.sid_length', 'session.upload_progress.cleanup',
    'session.upload_progress.enabled', 'session.upload_progress.freq', 'session.upload_progress.min_freq',
    'session.upload_progress.name', 'session.upload_progress.prefix', 'user_ini.cache_ttl',
    'user_ini.filename', 'xmlrpc_error_number', 'xmlrpc_errors', 'zend.detect_unicode', 'zend.multibyte',
    'zend.signal_check', 'zlib.output_compression_level',
];
$all = ini_get_all(null, false);
foreach ($names as $name) {
    echo $name, ': ', var_export(ini_get($name), true), ' ', var_export($all[$name] ?? 'missing', true), "\n";
}

// the old value ini_set() returns is the default too
var_dump(ini_set('default_socket_timeout', '5'), ini_get('default_socket_timeout'));
ini_restore('default_socket_timeout');
var_dump(ini_get('default_socket_timeout'));
