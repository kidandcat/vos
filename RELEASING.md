# Releasing

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The number in `lakefile.lean` and the latest numbered heading in `CHANGELOG.md` are the same string. `scripts/check-version.sh` fails the build when they differ.

The `## [Unreleased]` section is not a version. The check skips it and reads the next heading of the form `## [X.Y.Z]`.

## Cut a release

1. Move the `Unreleased` notes under a new heading `## [X.Y.Z] - YYYY-MM-DD`. Leave a fresh empty `## [Unreleased]` above it.
2. Set `version := v!"X.Y.Z"` in `lakefile.lean` to that same number.
3. Open a pull request. CI runs `scripts/check-version.sh`. Do not merge while that check is red.
4. After the pull request is on `main`, the maintainer creates the git tag `vX.Y.Z` and the GitHub release. CI does not push tags, and agents working in this repository do not create them.

`0.1.0` is the first release. Its changelog covers pull requests 1 through 5. The tag does not exist until the maintainer creates it.
