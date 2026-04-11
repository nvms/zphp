<?php
// covers: curl_init, curl_setopt, curl_setopt_array, curl_exec, curl_getinfo,
//   curl_error, curl_errno, curl_close, curl_reset, CURLOPT constants,
//   file_get_contents (http), json_encode, json_decode, date_default_timezone_set,
//   date, DateTime, DateTimeZone, ob_start, ob_get_clean, classes, interfaces,
//   enums, match, named arguments, constructor property promotion, generators,
//   closures, array_map, array_filter, implode, sprintf, $argv, $argc

interface Exportable {
    public function toArray(): array;
}

enum LogLevel: string {
    case DEBUG = 'debug';
    case INFO = 'info';
    case WARN = 'warn';
    case ERROR = 'error';
}

class Logger {
    private array $entries = [];

    public function __construct(private string $timezone = 'UTC') {
        date_default_timezone_set($this->timezone);
    }

    public function log(LogLevel $level, string $message, array $context = []): void {
        $this->entries[] = [
            'time' => date('Y-m-d H:i:s T'),
            'level' => $level->value,
            'message' => $message,
            'context' => $context,
        ];
    }

    public function getEntries(): array {
        return $this->entries;
    }

    public function format(): string {
        ob_start();
        foreach ($this->entries as $entry) {
            $ctx = '';
            if (count($entry['context']) > 0) {
                $parts = [];
                foreach ($entry['context'] as $k => $v) {
                    $parts[] = "$k=$v";
                }
                $ctx = ' [' . implode(', ', $parts) . ']';
            }
            echo "[{$entry['time']}] {$entry['level']}: {$entry['message']}$ctx\n";
        }
        return ob_get_clean();
    }
}

class HttpResponse implements Exportable {
    public function __construct(
        public readonly int $status,
        public readonly string $body,
        public readonly float $time,
        public readonly string $url,
        public readonly ?string $error = null
    ) {}

    public function ok(): bool {
        return $this->status >= 200 && $this->status < 300;
    }

    public function json(): mixed {
        return json_decode($this->body, true);
    }

    public function toArray(): array {
        return [
            'status' => $this->status,
            'body_length' => strlen($this->body),
            'time' => $this->time,
            'url' => $this->url,
            'ok' => $this->ok(),
        ];
    }
}

class SimpleCache {
    private array $store = [];

    public function get(string $key): ?HttpResponse {
        if (!isset($this->store[$key])) return null;
        $entry = $this->store[$key];
        if (time() > $entry['expires']) {
            unset($this->store[$key]);
            return null;
        }
        return $entry['response'];
    }

    public function set(string $key, HttpResponse $response, int $ttl = 60): void {
        $this->store[$key] = [
            'response' => $response,
            'expires' => time() + $ttl,
        ];
    }

    public function keys(): array {
        return array_keys($this->store);
    }
}

class HttpClient {
    private ?Logger $logger;
    private ?SimpleCache $cache;
    private array $defaultHeaders = [];

    public function __construct(?Logger $logger = null, ?SimpleCache $cache = null) {
        $this->logger = $logger;
        $this->cache = $cache;
    }

    public function setDefaultHeaders(array $headers): void {
        $this->defaultHeaders = $headers;
    }

    public function get(string $url, array $headers = []): HttpResponse {
        if ($this->cache) {
            $cached = $this->cache->get($url);
            if ($cached !== null) {
                $this->logger?->log(LogLevel::DEBUG, "cache hit", ['url' => $url]);
                return $cached;
            }
        }

        $response = $this->request('GET', $url, headers: $headers);

        if ($this->cache && $response->ok()) {
            $this->cache->set($url, $response);
        }

        return $response;
    }

    public function post(string $url, string $body, array $headers = []): HttpResponse {
        return $this->request('POST', $url, body: $body, headers: $headers);
    }

    private function request(string $method, string $url, ?string $body = null, array $headers = []): HttpResponse {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 10,
            CURLOPT_FOLLOWLOCATION => true,
        ]);

        if ($method !== 'GET') {
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        }
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        }

        $allHeaders = array_merge($this->defaultHeaders, $headers);
        if (count($allHeaders) > 0) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, $allHeaders);
        }

        $this->logger?->log(LogLevel::INFO, "$method request", ['url' => $url]);

        $result = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $time = curl_getinfo($ch, CURLINFO_TOTAL_TIME);
        $effectiveUrl = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
        $error = curl_errno($ch) > 0 ? curl_error($ch) : null;

        if ($error !== null) {
            $this->logger?->log(LogLevel::ERROR, "request failed", ['url' => $url, 'error' => $error]);
        } else {
            $this->logger?->log(LogLevel::DEBUG, "response received", ['status' => $status, 'time' => round($time, 3)]);
        }

        return new HttpResponse(
            status: $status,
            body: $result !== false ? $result : '',
            time: $time,
            url: $effectiveUrl,
            error: $error,
        );
    }
}

// helper: render a summary table using output buffering
function renderSummary(array $responses): string {
    ob_start();
    echo "--- request summary ---\n";
    foreach ($responses as $name => $resp) {
        $status = $resp->ok() ? 'OK' : 'FAIL';
        echo sprintf("  %-20s %s  %d  %.3fs\n", $name, $status, $resp->status, $resp->time);
    }
    echo "---\n";
    return ob_get_clean();
}

// generator: yield stats from responses
function responseStats(array $responses): Generator {
    foreach ($responses as $name => $resp) {
        yield $name => $resp->toArray();
    }
}

// -- simulate without network by using error responses --
date_default_timezone_set("America/New_York");

$logger = new Logger("America/New_York");
$cache = new SimpleCache();
$client = new HttpClient(logger: $logger, cache: $cache);
$client->setDefaultHeaders([
    "Accept: application/json",
    "User-Agent: zphp-test/1.0",
]);

// simulate responses (connection will fail but that exercises error handling)
$responses = [];

// test error handling path
$r1 = $client->get("http://127.0.0.1:1/api/users");
$responses['users'] = $r1;
echo "users ok: " . ($r1->ok() ? 'true' : 'false') . "\n";
echo "users error: " . ($r1->error !== null ? 'yes' : 'no') . "\n";

$r2 = $client->post("http://127.0.0.1:1/api/users", json_encode(['name' => 'alice']), [
    "Content-Type: application/json",
]);
$responses['create'] = $r2;
echo "create ok: " . ($r2->ok() ? 'true' : 'false') . "\n";

// test cache (second get to same URL should hit cache)
$r3 = $client->get("http://127.0.0.1:1/api/users");
$responses['users_cached'] = $r3;

// render summary
echo renderSummary($responses);

// generator stats
foreach (responseStats($responses) as $name => $stats) {
    echo "$name: status={$stats['status']} ok=" . ($stats['ok'] ? 'true' : 'false') . "\n";
}

// logger output
$log = $logger->format();
$lines = explode("\n", trim($log));
echo "log entries: " . count($lines) . "\n";

// verify timezone in log entries
$first = $lines[0];
echo "log has timezone: " . (strpos($first, 'EST') !== false || strpos($first, 'EDT') !== false ? 'true' : 'false') . "\n";

// cache state
echo "cache keys: " . count($cache->keys()) . "\n";

// datetime with timezone
$dt = new DateTime("now", new DateTimeZone("America/New_York"));
$tz = $dt->getTimezone();
echo "tz: " . $tz->getName() . "\n";

// serializable interface
echo "r1 serializable: " . ($r1 instanceof Exportable ? 'true' : 'false') . "\n";
$arr = $r1->toArray();
echo "toArray has status: " . (isset($arr['status']) ? 'true' : 'false') . "\n";
echo "toArray has ok: " . (isset($arr['ok']) ? 'true' : 'false') . "\n";

// enum match
$levels = [LogLevel::DEBUG, LogLevel::INFO, LogLevel::WARN, LogLevel::ERROR];
foreach ($levels as $l) {
    $icon = match($l) {
        LogLevel::DEBUG => 'D',
        LogLevel::INFO => 'I',
        LogLevel::WARN => 'W',
        LogLevel::ERROR => 'E',
    };
    echo "$icon:{$l->value} ";
}
echo "\n";

// $argv / $argc
echo "argv type: " . gettype($argv) . "\n";
echo "argc type: " . gettype($argc) . "\n";

echo "done\n";
