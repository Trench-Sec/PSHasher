# FileHasher

A lightweight PowerShell module that hashes **strings** or **files** using MD5, SHA1, SHA256, SHA384, or SHA512 — returning a structured object you can pipe, export, or compare inline.

---

## Requirements

| Environment | Minimum version |
|---|---|
| Windows PowerShell | 5.1 |
| PowerShell (Core) | 7.0+ |

No external dependencies. Uses only `System.Security.Cryptography` from the .NET standard library.

---

## Installation

1. Download `FileHasher.psm1` and `FileHasher.psd1` into a folder named `FileHasher`.
2. Move the folder to a directory on your module path:

```powershell
# Check your available module paths (cross-platform — works on Windows, Linux, macOS)
$env:PSModulePath -split [System.IO.Path]::PathSeparator

# Typical user-level location (Windows PowerShell 5.1)
$env:USERPROFILE\Documents\WindowsPowerShell\Modules\FileHasher\

# Typical user-level location (PowerShell 7+ on Windows)
$env:USERPROFILE\Documents\PowerShell\Modules\FileHasher\

# Typical user-level location (PowerShell 7+ on Linux / macOS)
~/.local/share/powershell/Modules/FileHasher/
```

3. Import the module:

```powershell
Import-Module FileHasher
```

To auto-import in every session, add that line to your `$PROFILE`.

---

## Usage

```
Get-Hash [-InputString <string>] [-Algorithm <string>] [-Encoding <string>] [-Uppercase]
Get-Hash  -FilePath    <string>  [-Algorithm <string>] [-Uppercase]
```

### Parameters

| Parameter | Applies to | Valid values | Default |
|---|---|---|---|
| `-InputString` | String mode | Any non-empty string | *(required)* |
| `-FilePath` | File mode | Literal file path | *(required)* |
| `-Algorithm` | Both | `MD5` `SHA1` `SHA256` `SHA384` `SHA512` | `SHA256` |
| `-Encoding` | String mode only | `UTF8` `UTF16LE` `UTF16BE` `ASCII` `UTF32` | `UTF8` |
| `-Uppercase` | Both | *(switch)* | off (lowercase) |

> **`-InputString` and `-FilePath` are mutually exclusive.** PowerShell will reject any call that supplies both.

### Output object

Every call returns a `PSCustomObject`:

```
Algorithm  : SHA256
InputType  : String        # or 'File'
Encoding   : UTF8          # $null when InputType is 'File'
Input      : Hello, World! # original string or resolved absolute path
Hash       : dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986d
```

---

## Examples

```powershell
# Hash a string (SHA256, UTF-8, lowercase — all defaults)
Get-Hash -InputString "Hello, World!"

# SHA512, uppercase
Get-Hash -InputString "Hello, World!" -Algorithm SHA512 -Uppercase

# File integrity check
Get-Hash -FilePath "C:\Downloads\installer.exe" -Algorithm SHA256

# Relative path, SHA384, uppercase
Get-Hash -FilePath ".\archive.zip" -Algorithm SHA384 -Uppercase

# Pipe multiple strings — each hashed individually
"apple", "banana", "cherry" | Get-Hash -Algorithm MD5

# Hash a string as UTF-16 LE bytes (matches Windows CNG / .NET default for Unicode strings)
Get-Hash -InputString "café" -Encoding UTF16LE

# Verify a download against a published checksum
$expected = "abc123..."
$result = Get-Hash -FilePath ".\download.zip" -Uppercase
if ($result.Hash -eq $expected) { "OK" } else { "MISMATCH" }

# Export a batch of file hashes to CSV
Get-ChildItem "C:\Deploy" -File |
    ForEach-Object { Get-Hash -FilePath $_.FullName } |
    Export-Csv "hashes.csv" -NoTypeInformation
```

---

## Nuances

### Encoding changes the hash
For string input, the encoding determines what bytes are passed to the hasher. `"Hello"` encoded as `UTF8` and as `UTF16LE` produce different byte sequences — and therefore different digests. Always agree on an encoding when sharing hashes with other systems.

| Encoding | When to use |
|---|---|
| `UTF8` | Default; compatible with most Unix/web tools |
| `UTF16LE` | Windows-native Unicode encoding; .NET's default internal string representation |
| `UTF16BE` | Interoperability with big-endian systems |
| `ASCII` | 7-bit ASCII only; **silently replaces non-ASCII characters with `?`** — `"café"` and `"cafe"` hash identically |
| `UTF32` | Rare; 4-byte fixed-width Unicode |

### FilePath uses literal semantics
`-FilePath` is resolved with `-LiteralPath`, so brackets and other wildcard characters in filenames are treated as literals, not glob patterns. If you need wildcard expansion, enumerate first:

```powershell
Get-ChildItem "C:\Logs\*.log" | ForEach-Object { Get-Hash -FilePath $_.FullName }
```

### MD5 and SHA1 on FIPS-enforced systems
Systems with the Windows FIPS security policy enabled (common in government/enterprise) will throw an `AlgorithmUnavailable` error if you request `MD5` or `SHA1`. Use `SHA256`, `SHA384`, or `SHA512` in those environments.

### Case sensitivity of the output digest
By default, hex output is lowercase. Use `-Uppercase` when comparing against a published checksum that is uppercase, to avoid false mismatches from string comparison.

---

## Tips

**Batch-hash an entire directory and spot duplicates**
```powershell
Get-ChildItem "C:\Data" -Recurse -File |
    ForEach-Object { Get-Hash -FilePath $_.FullName } |
    Group-Object Hash |
    Where-Object Count -gt 1 |
    Select-Object Count, @{n='Hash';e={$_.Name}}, @{n='Files';e={$_.Group.Input}}
```

**Compare a file against a known checksum in one line**
```powershell
(Get-Hash -FilePath ".\file.iso" -Uppercase).Hash -eq "EXPECTED_HASH_HERE"
```

**Hash every line of a text file**
```powershell
Get-Content "wordlist.txt" | Get-Hash -Algorithm SHA256 | Export-Csv "hashed.csv" -NoTypeInformation
```

**Store a baseline and detect tampering later**
```powershell
# Baseline
Get-Hash -FilePath "C:\App\config.xml" | Export-Clixml "config-baseline.xml"

# Later check
$baseline = Import-Clixml "config-baseline.xml"
$current  = Get-Hash -FilePath "C:\App\config.xml"
if ($current.Hash -ne $baseline.Hash) { Write-Warning "config.xml has changed!" }
```

**Format output as a simple `hash  filename` manifest (shasum-compatible)**
```powershell
Get-ChildItem ".\release\" -File |
    ForEach-Object { Get-Hash -FilePath $_.FullName -Algorithm SHA256 } |
    ForEach-Object { "$($_.Hash)  $($_.Input)" } |
    Set-Content "SHA256SUMS.txt"
```

---

## Built-in help

Full parameter documentation is available via `Get-Help`:

```powershell
Get-Help Get-Hash
Get-Help Get-Hash -Examples
Get-Help Get-Hash -Full
```
