<?php
// covers: PDO sqlite in-memory, prepared statements with named + positional
//   placeholders, transactions, rowCount, lastInsertId, fetch modes,
//   exception mode, parameter binding types

$db = new PDO('sqlite::memory:');
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

echo "=== schema setup ===\n";
$db->exec("CREATE TABLE bookings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    guest TEXT NOT NULL,
    room  TEXT NOT NULL,
    nights INTEGER NOT NULL,
    rate REAL NOT NULL,
    booked_at TEXT NOT NULL
)");
$db->exec("CREATE INDEX idx_room ON bookings(room)");
echo "tables: ok\n";

echo "\n=== insert with named placeholders ===\n";
$stmt = $db->prepare("INSERT INTO bookings (guest, room, nights, rate, booked_at) VALUES (:g, :r, :n, :p, :b)");
$rows = [
    ['Alice',  'A1', 3, 99.00, '2026-05-01'],
    ['Bob',    'B2', 1, 149.50, '2026-05-02'],
    ['Carol',  'A1', 2, 89.00, '2026-05-03'],
    ['Dave',   'C3', 5, 200.00, '2026-05-05'],
    ['Eve',    'B2', 2, 149.50, '2026-05-10'],
];
foreach ($rows as [$g, $r, $n, $p, $b]) {
    $stmt->execute([':g' => $g, ':r' => $r, ':n' => $n, ':p' => $p, ':b' => $b]);
}
echo "inserted: " . $stmt->rowCount() . " (last only)\n";
echo "lastInsertId: " . $db->lastInsertId() . "\n";

echo "\n=== count by room ===\n";
$q = $db->query("SELECT room, COUNT(*) AS n FROM bookings GROUP BY room ORDER BY room");
foreach ($q as $row) echo "  $row[room]: $row[n]\n";

echo "\n=== prepared select with positional placeholders ===\n";
$stmt = $db->prepare("SELECT guest, nights * rate AS subtotal FROM bookings WHERE room = ? ORDER BY booked_at");
$stmt->execute(['A1']);
foreach ($stmt->fetchAll() as $row) {
    echo sprintf("  %-6s %.2f\n", $row['guest'], $row['subtotal']);
}

echo "\n=== fetchColumn ===\n";
$stmt = $db->prepare("SELECT SUM(nights * rate) FROM bookings WHERE room = ?");
$stmt->execute(['B2']);
echo "B2 total: " . $stmt->fetchColumn() . "\n";

echo "\n=== bindValue with explicit type ===\n";
$stmt = $db->prepare("SELECT guest FROM bookings WHERE nights >= :min AND rate <= :max ORDER BY guest");
$stmt->bindValue(':min', 2, PDO::PARAM_INT);
$stmt->bindValue(':max', 150.0);
$stmt->execute();
foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $g) echo "  $g\n";

echo "\n=== transactions rollback ===\n";
$db->beginTransaction();
$db->exec("DELETE FROM bookings WHERE room = 'C3'");
$count_during = $db->query("SELECT COUNT(*) FROM bookings")->fetchColumn();
echo "during txn: $count_during rows\n";
$db->rollBack();
$count_after = $db->query("SELECT COUNT(*) FROM bookings")->fetchColumn();
echo "after rollback: $count_after rows\n";

echo "\n=== transactions commit ===\n";
$db->beginTransaction();
$stmt = $db->prepare("UPDATE bookings SET rate = rate * 1.10 WHERE room = ?");
$stmt->execute(['A1']);
$db->commit();
$stmt = $db->prepare("SELECT rate FROM bookings WHERE room = ? ORDER BY id");
$stmt->execute(['A1']);
foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $r) echo "  rate: " . round($r, 2) . "\n";

echo "\n=== exception on bad SQL ===\n";
try {
    $db->query("SELECT * FROM nonexistent");
    echo "no error\n";
} catch (PDOException $e) {
    echo "caught PDOException (good)\n";
}

echo "\n=== fetch into anonymous class ===\n";
class BookingRow {
    public string $guest = '';
    public int $nights = 0;
    public float $rate = 0.0;
}
$stmt = $db->prepare("SELECT guest, nights, rate FROM bookings ORDER BY id LIMIT 3");
$stmt->setFetchMode(PDO::FETCH_CLASS, BookingRow::class);
$stmt->execute();
foreach ($stmt as $row) {
    echo sprintf("  %-6s n=%d r=%.2f\n", $row->guest, $row->nights, $row->rate);
}

echo "\n=== aggregate output ===\n";
$tot = $db->query("SELECT COUNT(*) AS n, SUM(nights*rate) AS gross FROM bookings")->fetch();
echo "rows: $tot[n]  gross: " . round($tot['gross'], 2) . "\n";

echo "\ndone\n";
