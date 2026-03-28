#
# Module manifest for FileHasher
#
@{
    ModuleVersion        = '1.0.0'
    GUID                 = 'a3f2c1d4-8b7e-4f6a-9c3d-2e1b5a8f0c7d'
    Author               = ''
    Description          = 'Hash any string or file with MD5, SHA1, SHA256, SHA384, or SHA512.'
    PowerShellVersion    = '5.1'
    RootModule           = 'FileHasher.psm1'
    FunctionsToExport    = @('Get-Hash')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags = @('hash', 'sha256', 'md5', 'crypto', 'checksum')
        }
    }
}
