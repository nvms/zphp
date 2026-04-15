<?php
// session round-tripping of mixed types via $_SESSION.
// deletes its own file at the end so PHP and zphp runs don't interfere.

session_start();

// seed with various types
$_SESSION['count'] = 42;
$_SESSION['name'] = "alice";
$_SESSION['ratio'] = 0.75;
$_SESSION['flagged'] = true;
$_SESSION['absent'] = null;
$_SESSION['tags'] = ['admin', 'staff'];
$_SESSION['meta'] = ['created' => 1700000000, 'source' => 'test'];

session_write_close();

// reopen and verify every type survives
session_start();

echo "count: ";
var_dump($_SESSION['count']);
echo "name: ";
var_dump($_SESSION['name']);
echo "ratio: ";
var_dump($_SESSION['ratio']);
echo "flagged: ";
var_dump($_SESSION['flagged']);
echo "absent: ";
var_dump($_SESSION['absent']);
echo "tags: ";
var_dump($_SESSION['tags']);
echo "meta: ";
var_dump($_SESSION['meta']);

// strict comparisons (would fail if everything got stringified)
echo "int === 42: ";
var_dump($_SESSION['count'] === 42);
echo "bool === true: ";
var_dump($_SESSION['flagged'] === true);
echo "null === null: ";
var_dump($_SESSION['absent'] === null);
echo "nested int: ";
var_dump($_SESSION['meta']['created'] === 1700000000);

// status and id sanity
echo "status: ";
var_dump(session_status() === PHP_SESSION_ACTIVE);
echo "id len ok: ";
var_dump(strlen(session_id()) > 0);

session_destroy();
