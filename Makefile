PKG_CONFIG_PATH := /opt/homebrew/opt/mysql-client/lib/pkgconfig:/opt/homebrew/opt/libpq/lib/pkgconfig:/opt/homebrew/opt/openssl@3/lib/pkgconfig:$(PKG_CONFIG_PATH)
export PKG_CONFIG_PATH

.PHONY: build
build: ## Build zphp
	zig build

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

.PHONY: laravel
laravel: build ## Run Laravel compatibility tests (requires PHP 8.4 + composer)
	./tests/laravel/run

.PHONY: all-tests
all-tests: test compat pdo examples ## Run all tests

.PHONY: clean
clean: ## Clean build artifacts
	rm -rf zig-out .zig-cache

.PHONY: help
help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-20s\033[0m %s\n", $$1, $$2}'
