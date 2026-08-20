function List-SolutionProjects([string]$SolutionFilePath)
{
    $solutionFolderTypeGuid = '2150E333-8FDC-42A3-9474-1A3956D46DE8'
    $projects = @()
    $soltionFolder = Split-Path -Parent $SolutionFilePath
    Get-Content -LiteralPath $SolutionFilePath | ForEach-Object {
        $line = $_
        if ($line -notmatch '^Project\("\{(?<type>[^\}]+)\}"\)\s*=\s*"(?<name>[^"]+)",\s*"(?<path>[^"]+)",\s*"\{(?<guid>[^\}]+)\}"') {
            return
        }

        $typeGuid = $Matches['type']
        if ($typeGuid.Trim().ToUpperInvariant() -eq $solutionFolderTypeGuid.ToUpperInvariant()) {
            return
        }
        $relPath = $Matches['path']
        $fullPath = Resolve-Path -RelativeBase $soltionFolder -Path $relPath

        $projects += [PSCustomObject]@{
            Name = $Matches['name']
            Path = $fullPath
        }
    }
    return $projects
}
