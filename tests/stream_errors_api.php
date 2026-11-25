<?php
// php 8.6's stream errors api: the StreamErrorCode, StreamErrorMode and
// StreamErrorStore enums, the StreamError and StreamException classes, and
// stream_last_errors() and stream_clear_errors()

echo count(StreamErrorCode::cases()), " codes\n";
foreach (StreamErrorCode::cases() as $case) echo $case->name, "\n";
var_dump(StreamErrorMode::cases(), StreamErrorStore::cases());
var_dump(StreamErrorCode::OpenFailed instanceof UnitEnum);
var_dump(StreamErrorMode::Silent === StreamErrorMode::Silent);

echo new ReflectionClass('StreamError');
echo new ReflectionClass('StreamException');
echo new ReflectionEnum('StreamErrorMode');
echo new ReflectionEnum('StreamErrorStore');
echo new ReflectionFunction('stream_last_errors');
echo new ReflectionFunction('stream_clear_errors');

$r = new ReflectionClass('StreamError');
var_dump($r->isFinal(), $r->isReadOnly(), $r->getConstructor(), $r->getExtensionName());
foreach ($r->getProperties() as $p) {
    echo $p->getName(), ": ", $p->getType(), $p->isReadOnly() ? " readonly" : "", "\n";
}
var_dump((new ReflectionClass('StreamException'))->getParentClass()->getName());
var_dump((new ReflectionEnum('StreamErrorCode'))->getExtensionName());

// nothing stored yet
var_dump(stream_last_errors());
var_dump(stream_clear_errors());

// a StreamException made in php code carries no errors
$e = new StreamException("made by hand", 7);
var_dump($e->getErrors(), $e->getMessage(), $e->getCode());
var_dump($e);

// the readonly properties of a StreamError can't be written from outside
$error = (new ReflectionClass('StreamError'))->newInstanceWithoutConstructor();
try {
    $error->message = 'x';
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// the default context takes no error options
foreach (['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::All, 'error_handler' => 'var_dump'] as $option => $value) {
    try {
        stream_context_set_default(['stream' => [$option => $value]]);
    } catch (ValueError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
var_dump(stream_context_get_options(stream_context_get_default()));
