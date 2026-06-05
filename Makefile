PKG_CONFIG_PATH := /opt/homebrew/opt/mysql-client/lib/pkgconfig:/opt/homebrew/opt/libpq/lib/pkgconfig:/opt/homebrew/opt/openssl@3/lib/pkgconfig:/opt/homebrew/opt/curl/lib/pkgconfig:/opt/homebrew/opt/icu4c@77/lib/pkgconfig:/opt/homebrew/opt/icu4c/lib/pkgconfig:/opt/homebrew/opt/gmp/lib/pkgconfig:/opt/homebrew/opt/gd/lib/pkgconfig:/opt/homebrew/opt/libsodium/lib/pkgconfig:/opt/homebrew/opt/openldap/lib/pkgconfig:$(PKG_CONFIG_PATH)
export PKG_CONFIG_PATH

.PHONY: build
build: ## Build zphp (Debug; ~30x slower than release due to Zig's debug allocator stack-trace capture). use `make release` for benchmarking
	zig build

.PHONY: release
release: ## Build zphp in ReleaseFast (no debug allocator overhead). prefer for any perf-sensitive run; for testing zphp's actual PHP-execution speed
	zig build -Doptimize=ReleaseFast

.PHONY: test
test: ## Run zig unit tests
	zig build test

.PHONY: compat
compat: build ## Run PHP compatibility tests (requires PHP 8.4)
	./tests/run

.PHONY: pdo
pdo: build ## Run PDO driver tests
	./tests/pdo_test

.PHONY: examples
examples: build ## Run example project tests (requires PHP 8.4)
	./tests/examples_test

.PHONY: bench
bench: ## Run runtime benchmarks (ReleaseFast)
	zig build -Doptimize=ReleaseFast
	./benchmarks/runtime/run

.PHONY: bench-macro
bench-macro: ## Track real-app perf vs php (WordPress + Laravel harnesses, ReleaseFast)
	zig build -Doptimize=ReleaseFast
	./benchmarks/macro/run

.PHONY: laravel
laravel: build ## Run Laravel compatibility tests (requires PHP 8.4 + composer)
	./tests/laravel/run

.PHONY: all-tests
all-tests: test compat examples laravel ## Run all tests

.PHONY: docs
docs: ## Serve docs locally with live reload
	mdbook serve docs

.PHONY: clean
clean: ## Clean build artifacts
	rm -rf zig-out .zig-cache

.PHONY: help
help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-20s\033[0m %s\n", $$1, $$2}'
