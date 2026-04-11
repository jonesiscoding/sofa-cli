# SOFA CLI
## Overview

`sofa-cli` is a CLI tool designed to parse and extract data from the MacAdmins SOFA JSON feed. It simplifies the 
process of filtering the feed based on various criteria such as device, model, release date delay, and
version comparisons, with additional filtering and manipulation available using the syntax from `jq` In addition to
filtering, flags can be used to limit output to a single `SecurityRelease` object.

This tool has been released under the same license as the [macadmins/sofa](https://sofa.macadmins.io) project for your
convenience.

## Requirements

This tool should run on macOS 11+ and most Linux flavors. When running on macOS 13+, there are no additional 
dependencies.

### JQ

If running on Linux or versions of macOS older than v13, `sofa-cli` will attempt to locate `jq` automatically in the
path or various standard locations.  You can also specify a path with the environment variable JQ_BIN.

If not found, `sofa-cli` will attempt to install `jq` automatically. If JQ_BIN has been specified, that path is used,
otherwise `/usr/local/bin/jq` or `$HOME/.local/bin/jq` are used, depending on which location the user can write to.

## Usage

### Filtering

By default, the JSON contents of the SOFA feed are displayed, filtered by any given flags or additional `jq` queries.
The flags detailed below can be used to filter the results.  The built-in filters will remove entries from the 
`SecurityReleases` array of each `OSVersions` object when they do not match the filter.

| Flag       | Arguments                   | Only Releases                                                           |
|------------|-----------------------------|-------------------------------------------------------------------------|
| `--device` | Device ID (optional)        | Supporting the given device. <br/>Device will be detected if not given* |
| `--model`  | Model Identifier (optional) | Supporting the given model. <br/>Model will be detected if not given*   |
| `--delay`  | Delay in Days               | With a `ReleaseDate` more than X days ago.                              |                                                                      
| `--gt`     | Version                     | With a `ProductVerison` > the given version.                            |
| `--gte`    | Version                     | With a `ProductVerison` >= than the given version.                      |
| `--lt`     | Version                     | With a `ProductVerison` < than the given version.                       |
| `--lte`    | Version                     | With a `ProductVerison` <= than the given version.                      |
| `--eq`     | Version                     | With a `ProductVerison` == to the given version.                        |

    * When run on macOS 

#### Comparison Filtering

Comparison filtering uses the version parts given, and assumes a _.x_ for any left out minor or revision increment. This
allows for filtering results to all the minor and revision increments within a given version.

See the examples below for a better explanation.

| Flag          | Treated As | Result                   |
|---------------|------------|--------------------------|
| `--eq 15`     | = 15.x.x   | All Sequoia Releases     |
| `--eq 15.0`   | = 15.0.x   | Only _15.0_ and _15.0.1_ |
| `--eq 15.0.0` | = 15.0.0   | Only _15.0_              |

### SecurityRelease Object Flags

| Flag       | Arguments | Results                                                                                                                                                      |
|------------|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `--latest` |           | Displays JSON object for the latest `SecurityRelease` present, after filtering.                                                                              |
| `--next`   | Version   | Displays JSON object for the next incremental version, after filtering. <br/>If a version is not given, it will default to the currently installed version.* |

    * When run on macOS 

### Additional Filtering and Manipulation

Any syntax that works on `jq` can be added after the flags detailed above.  By default, the additional arguments are
applied to the JSON of the SOFA feed, after any previous filtering has been performed.  

If a `SecurityRelease` flag is used, the additional arguments will be applied to the `SecurityRelease` object.  
For example, the following would display only  the version number of the latest version available for the 2020 
13" M1 MacBook Pro.

```bash
sofa --model Mac15,13 --latest '.ProductVersion'
```

### Additional Examples

```bash
# Example 1: Filter JSON by delay and extract a specific property using JQ query language
sofa --delay 30 --latest '.ProductVersion'

# Example 2:  Filter JSON by model return the latest SecurityRelease object.  
#
# Example 2a: 26.4 will be returned. 26.3.2 is skipped as it does not apply to the model.
sofa --model "Mac16,1" --next 26.3.1
# Example 2b: 26.3.2 will be returned for the Macbook Neo
sofa --model "Mac17,5" --next 26.3.1

# Example 3: Filter JSON by version less than or equal to a specific version
sofa --lte 15.7
```

## Help Options

| Flag        | Arguments | Results                 |
|-------------|-----------|-------------------------|
| `--help`    |           | Displays Help           |
| `--version` |           | Displays Name & Version |

## Exit Codes

- `0`: Successful operation.
- `1`: Generic error (e.g., JSON retrieval failure).
- `2`: Required dependency (`jq`) not found.

