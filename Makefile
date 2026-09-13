.PHONY: get analyze format format-check test publish-dry-run

get:
	flutter pub get

analyze:
	dart analyze

format:
	dart format -l 120 lib test example

format-check:
	dart format --output=none --set-exit-if-changed lib test example

test:
	flutter test

publish-dry-run:
	dart pub publish --dry-run
