<?php
// php refuses a generator whose declared return type cannot hold a Generator
echo "not printed\n";
function admitted(): iterable {
    yield 1;
}
function refused(): stdClass|array {
    yield 1;
}
