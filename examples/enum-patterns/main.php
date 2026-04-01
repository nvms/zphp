<?php
// covers: unit enums, string-backed enums, int-backed enums, enum methods, enum interfaces, enum constants, Enum::from, Enum::tryFrom, Enum::cases, enum match, enum comparison, enum in arrays, enum static methods, enum name property, enum value property

// --- unit enums ---

enum Suit {
    case Hearts;
    case Diamonds;
    case Clubs;
    case Spades;
}

$suit = Suit::Hearts;
echo "Unit enum name: " . $suit->name . "\n";
echo "Hearts === Hearts: " . ($suit === Suit::Hearts ? "true" : "false") . "\n";
echo "Hearts === Clubs: " . ($suit === Suit::Clubs ? "true" : "false") . "\n";

// --- string-backed enums ---

enum Color: string {
    case Red = 'red';
    case Green = 'green';
    case Blue = 'blue';
}

$color = Color::Red;
echo "String backed name: " . $color->name . "\n";
echo "String backed value: " . $color->value . "\n";

$fromValue = Color::from('green');
echo "from('green') name: " . $fromValue->name . "\n";
echo "from('green') value: " . $fromValue->value . "\n";

$tryValid = Color::tryFrom('blue');
echo "tryFrom('blue') name: " . $tryValid->name . "\n";

$tryInvalid = Color::tryFrom('yellow');
echo "tryFrom('yellow') is null: " . ($tryInvalid === null ? "true" : "false") . "\n";

// --- int-backed enums ---

enum HttpStatus: int {
    case OK = 200;
    case NotFound = 404;
    case ServerError = 500;
}

$status = HttpStatus::OK;
echo "Int backed name: " . $status->name . "\n";
echo "Int backed value: " . $status->value . "\n";

$fromInt = HttpStatus::from(404);
echo "from(404) name: " . $fromInt->name . "\n";

$tryInt = HttpStatus::tryFrom(999);
echo "tryFrom(999) is null: " . ($tryInt === null ? "true" : "false") . "\n";

// --- Enum::cases() ---

echo "Suit cases:\n";
$cases = Suit::cases();
foreach ($cases as $case) {
    echo "  " . $case->name . "\n";
}

echo "Color cases:\n";
$colorCases = Color::cases();
foreach ($colorCases as $case) {
    echo "  " . $case->name . " = " . $case->value . "\n";
}

// --- enum methods ---

enum Direction {
    case North;
    case South;
    case East;
    case West;

    public function opposite(): Direction {
        return match($this) {
            Direction::North => Direction::South,
            Direction::South => Direction::North,
            Direction::East => Direction::West,
            Direction::West => Direction::East,
        };
    }

    public function label(): string {
        return match($this) {
            Direction::North => "Up",
            Direction::South => "Down",
            Direction::East => "Right",
            Direction::West => "Left",
        };
    }
}

$dir = Direction::North;
echo "North opposite: " . $dir->opposite()->name . "\n";
echo "North label: " . $dir->label() . "\n";
echo "East opposite: " . Direction::East->opposite()->name . "\n";

// --- enum implementing interfaces ---

interface HasDescription {
    public function description(): string;
}

enum Season: string implements HasDescription {
    case Spring = 'spring';
    case Summer = 'summer';
    case Autumn = 'autumn';
    case Winter = 'winter';

    public function description(): string {
        return match($this) {
            Season::Spring => "Flowers bloom",
            Season::Summer => "Sun shines",
            Season::Autumn => "Leaves fall",
            Season::Winter => "Snow falls",
        };
    }
}

$season = Season::Autumn;
echo "Season name: " . $season->name . "\n";
echo "Season value: " . $season->value . "\n";
echo "Season description: " . $season->description() . "\n";

// --- enum with multiple cases ---

enum Size {
    case Small;
    case Medium;
    case Large;
}

echo "Size Small name: " . Size::Small->name . "\n";
echo "Size Large name: " . Size::Large->name . "\n";

// --- enum in match expressions ---

function describeStatus(HttpStatus $s): string {
    return match($s) {
        HttpStatus::OK => "Success",
        HttpStatus::NotFound => "Not Found",
        HttpStatus::ServerError => "Server Error",
    };
}

echo "200 status: " . describeStatus(HttpStatus::OK) . "\n";
echo "404 status: " . describeStatus(HttpStatus::NotFound) . "\n";
echo "500 status: " . describeStatus(HttpStatus::ServerError) . "\n";

// --- enum in arrays ---

$statusMessages = [];
$statusMessages[HttpStatus::OK->value] = "All good";
$statusMessages[HttpStatus::NotFound->value] = "Page missing";
$statusMessages[HttpStatus::ServerError->value] = "Something broke";

echo "Status 200 message: " . $statusMessages[200] . "\n";
echo "Status 404 message: " . $statusMessages[404] . "\n";

$favorites = [Color::Red, Color::Blue];
echo "Favorite count: " . count($favorites) . "\n";
echo "First favorite: " . $favorites[0]->name . "\n";
echo "Second favorite: " . $favorites[1]->name . "\n";

// --- enum static methods ---

enum Currency: string {
    case USD = 'USD';
    case EUR = 'EUR';
    case GBP = 'GBP';

    public static function fromSymbol(string $symbol): self {
        return match($symbol) {
            '$' => self::USD,
            'E' => self::EUR,
            'P' => self::GBP,
            default => throw new \ValueError("Unknown symbol: $symbol"),
        };
    }

    public function symbol(): string {
        return match($this) {
            self::USD => '$',
            self::EUR => 'E',
            self::GBP => 'P',
        };
    }
}

$usd = Currency::fromSymbol('$');
echo "From symbol '$': " . $usd->name . "\n";
echo "USD symbol: " . Currency::USD->symbol() . "\n";
echo "EUR symbol: " . Currency::EUR->symbol() . "\n";

$caughtSymbol = false;
try {
    Currency::fromSymbol('?');
} catch (\ValueError $e) {
    $caughtSymbol = true;
}
echo "Unknown symbol throws: " . ($caughtSymbol ? "true" : "false") . "\n";

// --- enum comparison ---

$a = Suit::Hearts;
$b = Suit::Hearts;
$c = Suit::Clubs;

echo "Same case ===: " . ($a === $b ? "true" : "false") . "\n";
echo "Different case ===: " . ($a === $c ? "true" : "false") . "\n";
