$here = $PSScriptRoot

foreach ($file in Get-ChildItem -Path (Join-Path $here 'Private') -Filter '*.ps1') {
    . $file.FullName
}

foreach ($file in Get-ChildItem -Path (Join-Path $here 'Public') -Filter '*.ps1') {
    . $file.FullName
}

Export-ModuleMember -Function (Get-ChildItem -Path (Join-Path $here 'Public') -Filter '*.ps1').BaseName
