import urllib.request
import time
import concurrent.futures
import sys

REQUESTS = 1000
CONCURRENCY = 50

targets = [
    ("php-fpm", "http://localhost:9081/"),
    ("swoole", "http://localhost:9082/"),
    ("zphp", "http://localhost:9083/"),
]

def do_request(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            r.read()
            return True
    except:
        return False

for name, url in targets:
    successes = 0
    start = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
        futures = [pool.submit(do_request, url) for _ in range(REQUESTS)]
        for f in concurrent.futures.as_completed(futures):
            if f.result():
                successes += 1

    elapsed = time.time() - start
    rps = successes / elapsed if elapsed > 0 else 0
    print(f"  {name:12s}  {successes}/{REQUESTS} ok  {elapsed:.2f}s  {rps:.0f} req/s")
