<?php
// covers: date_default_timezone_set, date_default_timezone_get, DateTime,
//   DateTimeZone, DateInterval, date, mktime, strtotime, ob_start,
//   ob_get_clean, ob_get_level, classes, enums, match, array_map,
//   array_filter, usort, implode, sprintf, json_encode, constructor
//   property promotion, readonly properties, named arguments, generators,
//   nullsafe operator

enum Priority: int {
    case LOW = 1;
    case MEDIUM = 2;
    case HIGH = 3;
    case CRITICAL = 4;
}

class Event {
    public function __construct(
        public readonly string $name,
        public readonly int $timestamp,
        public readonly string $timezone,
        public readonly Priority $priority = Priority::MEDIUM
    ) {}

    public function formatIn(string $tz): string {
        $dt = new DateTime("@{$this->timestamp}");
        $dt->setTimezone(new DateTimeZone($tz));
        return $dt->format('Y-m-d H:i:s T');
    }

    public function isPast(): bool {
        return $this->timestamp < time();
    }
}

class Schedule {
    private array $events = [];

    public function add(Event $event): void {
        $this->events[] = $event;
    }

    public function upcoming(): array {
        $now = time();
        $upcoming = array_filter($this->events, fn($e) => $e->timestamp >= $now);
        usort($upcoming, fn($a, $b) => $a->timestamp - $b->timestamp);
        return $upcoming;
    }

    public function past(): array {
        $now = time();
        return array_filter($this->events, fn($e) => $e->timestamp < $now);
    }

    public function byPriority(Priority $p): array {
        return array_filter($this->events, fn($e) => $e->priority === $p);
    }

    public function all(): array {
        $sorted = $this->events;
        usort($sorted, fn($a, $b) => $a->timestamp - $b->timestamp);
        return $sorted;
    }

    public function render(string $viewerTz): string {
        ob_start();
        echo "=== Schedule (viewing in $viewerTz) ===\n";
        foreach ($this->all() as $event) {
            $label = match($event->priority) {
                Priority::LOW => '[ ]',
                Priority::MEDIUM => '[*]',
                Priority::HIGH => '[!]',
                Priority::CRITICAL => '[X]',
            };
            echo sprintf("  %s %s - %s (source: %s)\n",
                $label,
                $event->formatIn($viewerTz),
                $event->name,
                $event->timezone
            );
        }
        echo "=== " . count($this->events) . " events ===\n";
        return ob_get_clean();
    }
}

// use fixed timestamps for deterministic output
$base = 1704067200; // 2024-01-01 00:00:00 UTC

$schedule = new Schedule();

// events created in different timezones
date_default_timezone_set("America/New_York");
$schedule->add(new Event(
    name: "Team standup",
    timestamp: $base + 9 * 3600, // 9am UTC = 4am EST
    timezone: date_default_timezone_get(),
    priority: Priority::HIGH,
));

date_default_timezone_set("Europe/London");
$schedule->add(new Event(
    name: "London sync",
    timestamp: $base + 14 * 3600, // 2pm UTC
    timezone: date_default_timezone_get(),
    priority: Priority::MEDIUM,
));

date_default_timezone_set("Asia/Tokyo");
$schedule->add(new Event(
    name: "Tokyo review",
    timestamp: $base + 1 * 3600, // 1am UTC = 10am JST
    timezone: date_default_timezone_get(),
    priority: Priority::LOW,
));

date_default_timezone_set("America/Los_Angeles");
$schedule->add(new Event(
    name: "Deploy window",
    timestamp: $base + 20 * 3600, // 8pm UTC = 12pm PST
    timezone: date_default_timezone_get(),
    priority: Priority::CRITICAL,
));

// render from different viewer perspectives
echo $schedule->render("UTC");
echo "\n";
echo $schedule->render("America/New_York");
echo "\n";
echo $schedule->render("Asia/Tokyo");

// test timezone conversions
echo "\n--- timezone math ---\n";
date_default_timezone_set("UTC");
$dt = new DateTime("2024-07-01 12:00:00", new DateTimeZone("UTC"));
echo "UTC:      " . $dt->format("H:i T") . "\n";

$dt->setTimezone(new DateTimeZone("America/New_York"));
echo "New York: " . $dt->format("H:i T") . "\n";

$dt->setTimezone(new DateTimeZone("Europe/Paris"));
echo "Paris:    " . $dt->format("H:i T") . "\n";

$dt->setTimezone(new DateTimeZone("Asia/Tokyo"));
echo "Tokyo:    " . $dt->format("H:i T") . "\n";

$dt->setTimezone(new DateTimeZone("Asia/Kolkata"));
echo "Kolkata:  " . $dt->format("H:i T") . "\n";

// test DateTimeZone::getOffset with summer/winter
echo "\n--- DST offsets ---\n";
$tz_ny = new DateTimeZone("America/New_York");

$winter = new DateTime("2024-01-15 12:00:00", new DateTimeZone("UTC"));
$summer = new DateTime("2024-07-15 12:00:00", new DateTimeZone("UTC"));
echo "NY winter offset: " . $tz_ny->getOffset($winter) . "\n";
echo "NY summer offset: " . $tz_ny->getOffset($summer) . "\n";

$tz_paris = new DateTimeZone("Europe/Paris");
echo "Paris winter offset: " . $tz_paris->getOffset($winter) . "\n";
echo "Paris summer offset: " . $tz_paris->getOffset($summer) . "\n";

$tz_tokyo = new DateTimeZone("Asia/Tokyo");
echo "Tokyo offset: " . $tz_tokyo->getOffset($winter) . "\n";

// test date format specifiers
echo "\n--- format specifiers ---\n";
date_default_timezone_set("America/New_York");
echo date("e", $base) . "\n";
echo date("T", $base) . "\n";
echo date("P", $base) . "\n";
echo date("O", $base) . "\n";

// ISO 8601
echo date("c", $base) . "\n";

// filter by priority
$critical = $schedule->byPriority(Priority::CRITICAL);
echo "\ncritical events: " . count($critical) . "\n";
echo "name: " . $critical[array_key_first($critical)]->name . "\n";

echo "\ndone\n";
