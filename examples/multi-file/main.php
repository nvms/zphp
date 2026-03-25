<?php
// covers: require with __DIR__, require_once, multi-file class loading,
//   singleton pattern (static::$instance, new self), static properties/methods
//   across files, constants defined in required files, function defined in
//   required file, cross-file class dependencies (UserRepository requires
//   Database.php and uses Logger from another require), is_bool, str_pad,
//   str_repeat, preg_replace, array_keys, null coalescing, string interpolation,
//   static method calls, private constructor

require __DIR__ . "/helpers.php";
require __DIR__ . "/Logger.php";
require __DIR__ . "/UserRepository.php";

// === test: constants from required file ===

echo APP_NAME . " v" . APP_VERSION . "\n";

// === test: function from required file ===

echo slugify("Hello World Example") . "\n";
echo slugify("  PHP is GREAT!  ") . "\n";

// === test: cross-file singleton ===

$logger = new Logger("app");
$repo = new UserRepository($logger);

$repo->create("Alice", "alice@example.com");
$repo->create("Bob", "bob@example.com");
$repo->create("Charlie", "charlie@example.com");

echo "users: " . $repo->count() . "\n";

// === test: query data from required class ===

$alice = $repo->findByEmail("alice@example.com");
echo "found: " . $alice["name"] . "\n";

$missing = $repo->findByEmail("nobody@example.com");
echo "missing: " . ($missing === null ? "null" : "found") . "\n";

// === test: singleton identity across files ===

$db1 = Database::getInstance();
$db2 = Database::getInstance();
echo "same instance: " . ($db1 === $db2 ? "yes" : "no") . "\n";

// === test: static properties shared across instances ===

$tables = $db1->getTableNames();
echo "tables: " . implode(", ", $tables) . "\n";

// === test: logger collected entries across calls ===

$logger->error("something went wrong");
$logs = Logger::getAll();
echo "log count: " . count($logs) . "\n";
foreach ($logs as $entry) {
    echo "  $entry\n";
}

// === test: format helper with data from repo ===

$users = $repo->findAll();
echo formatTable($users, ["id", "name", "email", "active"]);

// === test: require_once (should not re-declare) ===

require_once __DIR__ . "/helpers.php";
require_once __DIR__ . "/Logger.php";
echo "require_once: ok\n";

// === test: second logger shares static state ===

$logger2 = new Logger("db");
$logger2->info("connected");
echo "total logs: " . count(Logger::getAll()) . "\n";

echo "done\n";
