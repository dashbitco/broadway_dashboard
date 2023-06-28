# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2023-06-28

### Added

- Add support for Phoenix LiveDashboard `~> 0.8.0`. Now this is the only supported version.
  Thanks [@moxley](https://github.com/moxley).

### Fixed

- Improve Telemetry performance by using a handler with module name.
  Thanks [@louisvisser](https://github.com/louisvisser).

### Removed

- Remove support for previous versions of Phoenix LiveDashboard. Now only `v0.8` is supported.

## [0.3.0] - 2022-10-03

### Added

- Add support for Phoenix LiveDashboard `~> 0.7.0`. Thanks [@walter](https://github.com/walter).

### Removed

- Remove support for Elixir v1.11. Thanks [@walter](https://github.com/walter).

## [0.2.2] - 2021-10-21

### Added

- Add support for Phoenix LiveDashboard `~> 0.6.0`

## [0.2.1] - 2021-09-08

### Fixed

- Fix crash when a pipeline is named using `:via`.

## [0.2.0] - 2021-09-07

### Added

- Add support for Broadway names that are pids or named using `:via`.

## [0.1.0] - 2021-08-30

### Added

- Initial release of Broadway Dashboard.

[Unreleased]: https://github.com/dashbitco/broadway_dashboard/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/dashbitco/broadway_dashboard/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/dashbitco/broadway_dashboard/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/dashbitco/broadway_dashboard/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/dashbitco/broadway_dashboard/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/dashbitco/broadway_dashboard/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dashbitco/broadway_dashboard/releases/tag/v0.1.0
