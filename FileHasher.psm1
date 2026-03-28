#Requires -Version 5.1
<#
.SYNOPSIS
    A PowerShell module for hashing strings and files using various algorithms.

.DESCRIPTION
    FileHasher exposes a single function, Get-Hash, which accepts either a
    plain-text string or a file path and returns a deterministic hex digest
    using the hashing algorithm of your choice.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+ (Core).
#>

function Get-Hash {
    <#
    .SYNOPSIS
        Hashes a string or file using the specified algorithm.

    .DESCRIPTION
        Accepts a plain-text string or a file path and returns a structured
        object containing the algorithm used, input type, original input, and
        resulting hex digest.

        Supports MD5, SHA1, SHA256, SHA384, and SHA512.

        Note: MD5 and SHA1 may be unavailable on FIPS-enforced systems.
        This includes Windows Group Policy FIPS mode and Linux kernel FIPS
        mode (/proc/sys/crypto/fips_enabled). Use SHA256 or higher instead.

    .PARAMETER InputString
        The plain-text string to hash. Mutually exclusive with -FilePath.
        Accepts pipeline input.

    .PARAMETER FilePath
        Path to the file to hash. Mutually exclusive with -InputString.
        Supports relative and absolute paths. Wildcards are NOT expanded
        (literal path semantics).

    .PARAMETER Algorithm
        Hashing algorithm to use.
        Valid values: MD5, SHA1, SHA256, SHA384, SHA512.
        Default: SHA256.

    .PARAMETER Encoding
        Text encoding used when converting a string to bytes before hashing.
        Only applies when using -InputString.
        Valid values: UTF8, UTF16LE, UTF16BE, ASCII, UTF32.
        Default: UTF8.

        Encoding affects the resulting hash — "Hello" encoded as UTF8
        produces a different digest than "Hello" encoded as UTF16LE.

    .PARAMETER Uppercase
        When specified, the hex digest is returned in uppercase.
        Default: lowercase.

    .EXAMPLE
        Get-Hash -InputString "Hello, World!"
        # SHA256 of the string using UTF-8 encoding (lowercase).

    .EXAMPLE
        Get-Hash -InputString "Hello, World!" -Algorithm SHA512 -Uppercase
        # SHA512 hash in uppercase hex.

    .EXAMPLE
        Get-Hash -FilePath "C:\report.pdf" -Algorithm MD5
        # MD5 checksum of the specified file.

    .EXAMPLE
        Get-Hash -FilePath ".\archive.zip" -Algorithm SHA384 -Uppercase
        # SHA384 hash of a file using a relative path, uppercase output.

    .EXAMPLE
        "password1", "password2", "password3" | Get-Hash -Algorithm SHA1
        # Pipe multiple strings; each is hashed individually.

    .EXAMPLE
        Get-Hash -InputString "cafe" -Encoding UTF16LE
        # Hash the string using UTF-16 LE byte representation.

    .OUTPUTS
        [PSCustomObject] with properties:
            Algorithm  [string]  - Algorithm used
            InputType  [string]  - 'String' or 'File'
            Encoding   [string]  - Encoding used (String mode only; $null for File)
            Input      [string]  - Original string or resolved file path
            Hash       [string]  - Hex digest
    #>
    [CmdletBinding(DefaultParameterSetName = 'String')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(
            Mandatory         = $true,
            ParameterSetName  = 'String',
            ValueFromPipeline = $true,
            HelpMessage       = 'Plain-text string to hash.'
        )]
        [ValidateNotNullOrEmpty()]
        [string] $InputString,

        [Parameter(
            Mandatory        = $true,
            ParameterSetName = 'File',
            HelpMessage      = 'Literal path to the file to hash.'
        )]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter()]
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA384', 'SHA512')]
        [string] $Algorithm = 'SHA256',

        [Parameter(ParameterSetName = 'String')]
        [ValidateSet('UTF8', 'UTF16LE', 'UTF16BE', 'ASCII', 'UTF32')]
        [string] $Encoding = 'UTF8',

        [Parameter()]
        [switch] $Uppercase
    )

    process {
        # ── Instantiate the hasher ────────────────────────────────────────────
        # HashAlgorithm.Create(string) is obsolete and returns $null in .NET 5+
        # (PowerShell 7.1+). Always use concrete type factories instead.
        $hasher = $null
        try {
            $hasher = switch ($Algorithm) {
                'MD5'    { [System.Security.Cryptography.MD5]::Create()    }
                'SHA1'   { [System.Security.Cryptography.SHA1]::Create()   }
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA384' { [System.Security.Cryptography.SHA384]::Create() }
                'SHA512' { [System.Security.Cryptography.SHA512]::Create() }
            }
        }
        catch [System.Security.Cryptography.CryptographicException] {
            # Windows FIPS policy blocks MD5 and SHA1 with CryptographicException.
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Algorithm '$Algorithm' is not available on this system. " +
                        "FIPS security policy may be enforced. " +
                        "Use SHA256, SHA384, or SHA512 instead."
                    ),
                    'AlgorithmUnavailable',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $Algorithm
                )
            )
            return
        }
        catch [System.PlatformNotSupportedException] {
            # Linux kernel FIPS mode (.NET 7+) raises PlatformNotSupportedException
            # instead of CryptographicException for MD5 and SHA1.
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Algorithm '$Algorithm' is not supported on this platform. " +
                        "FIPS mode may be enabled at the OS level. " +
                        "Use SHA256, SHA384, or SHA512 instead."
                    ),
                    'AlgorithmUnavailable',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $Algorithm
                )
            )
            return
        }

        try {
            # ── Compute the hash ──────────────────────────────────────────────
            # switch-as-expression enumerates byte[] into Object[] in some PS
            # versions, which breaks BitConverter. Use if/else with explicit
            # [byte[]] typing. Stream and hasher are disposed in a single flat
            # finally so neither masks exceptions from the other.
            [byte[]] $hashBytes = $null
            $inputLabel         = $null   # untyped: must remain $null-able for PSCustomObject
            $encodingLabel      = $null   # untyped: must stay $null for File mode (not "")
            $stream             = $null   # NOTE: [string] $x = $null coerces to "" in PowerShell

            try {
                if ($PSCmdlet.ParameterSetName -eq 'String') {
                    $enc = switch ($Encoding) {
                        'UTF8'    { [System.Text.Encoding]::UTF8             }
                        'UTF16LE' { [System.Text.Encoding]::Unicode          }
                        'UTF16BE' { [System.Text.Encoding]::BigEndianUnicode }
                        # ASCII silently replaces unmapped characters (e.g. accented letters)
                        # with '?' before hashing. Hashing "cafe" and "cafe-with-accent" both
                        # yield the same digest under ASCII. Use UTF8 for non-ASCII input.
                        'ASCII'   { [System.Text.Encoding]::ASCII            }
                        'UTF32'   { [System.Text.Encoding]::UTF32            }
                    }
                    [byte[]] $rawBytes  = $enc.GetBytes($InputString)
                    [byte[]] $hashBytes = $hasher.ComputeHash($rawBytes)
                    $inputLabel         = $InputString
                    $encodingLabel      = $Encoding
                }
                else {
                    # Resolve once and reuse — avoids a second disk round-trip
                    # and eliminates a TOCTOU race between resolve and open.
                    $resolved   = Resolve-Path -LiteralPath $FilePath -ErrorAction Stop
                    $inputLabel = $resolved.ProviderPath
                    $stream     = [System.IO.File]::OpenRead($inputLabel)
                    [byte[]] $hashBytes = $hasher.ComputeHash($stream)
                    # $encodingLabel intentionally stays $null for File mode
                }
            }
            finally {
                if ($null -ne $stream) { $stream.Dispose() }
            }

            # ── Format the hex digest ─────────────────────────────────────────
            $hex = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
            $hex = if ($Uppercase.IsPresent) { $hex.ToUpper() } else { $hex.ToLower() }

            # ── Emit result object ────────────────────────────────────────────
            [PSCustomObject]@{
                Algorithm  = $Algorithm
                InputType  = $PSCmdlet.ParameterSetName
                Encoding   = $encodingLabel
                Input      = $inputLabel
                Hash       = $hex
            }
        }
        finally {
            if ($null -ne $hasher) { $hasher.Dispose() }
        }
    }
}

Export-ModuleMember -Function Get-Hash
