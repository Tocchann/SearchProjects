function Generate-ProjectInfo( $prjFilePath )
{
    # $Root とあとで比較処理するので相対パスとして取り出す
    $relativePath = Resolve-Path -RelativeBase $Root -Path $prjFilePath -Relative

    $project = [PSCustomObject]@{
        Project = $relativePath
        Type = [System.IO.Path]::GetExtension($prjFilePath)
        Configurations = @()
        Platforms = @()
    }
    [xml]$prj = Get-Content $prjFilePath
    # vcxproj は ProjectConfiguration という項目がある可能性があるのでこちらの優先取得を試みる
    $reqestCondition = $true
    if( $project.Type -eq ".vcxproj" )
    {
        $projectConfigrations = $prj.Project.ItemGroup.ProjectConfiguration
        foreach( $projectConfig in $projectConfigrations )
        {
            $reqestCondition = $false
            $configValue = $projectConfig.Configuration
            $platformValue = $projectConfig.Platform
            if( -not [string]::IsNullOrEmpty($configValue) -and $project.Configurations -notcontains $configValue )
            {
                $project.Configurations += $configValue
            }
            if( -not [string]::IsNullOrEmpty($platformValue) -and $project.Platforms -notcontains $platformValue )
            {
                $project.Platforms += $platformValue
            }
        }
    }
    # csproj の旧形式
    if( $reqestCondition )
    {
        foreach( $prjGrp in $prj.Project.PropertyGroup )
        {
            $condition = $prjGrp.Condition?.Trim()
            if( [string]::IsNullOrEmpty($condition) )
            {
                continue
            }
            if( $condition -match "'\$\((?<config>Configuration)\)\|\$\((?<platform>Platform)\)' *== *'(?<configValue>[^']+)\|(?<platformValue>[^']+)'" )
            {
                $reqestCondition = $false
                $configValue = $matches['configValue']
                $platformValue = $matches['platformValue']
                # 複数回出現するので、情報の重複を避けるため絞り込みしておく
                if( $project.Configurations -notcontains $configValue )
                {
                    $project.Configurations += $configValue
                }
                if( $project.Platforms -notcontains $platformValue )
                {
                    $project.Platforms += $platformValue
                }
            }
        }
    }
    # csproj のSDK形式のはず…
    if( $reqestCondition )
    {
        # 設定がない場合はこれをセットアップしておけばよい
        if( $prj.Project.Sdk -eq "Microsoft.NET.Sdk" )
        {
            $project.Configurations += "Debug"
            $project.Configurations += "Release"
            $project.Platforms += "AnyCPU"
        }
    }
    return $project
}
function Search-ProjectFiles
{
    param(
        [Parameter(Mandatory=$true)]
        [string]$Root
    )
    Write-Host "$Root 内のプロジェクトを検索中..."
    $projects = @()
    # $Root 配下にあるすべてのプロジェクトファイルを列挙する。実際に使うかどうかは考慮しない
    $prjFiles = Get-ChildItem -Path $Root -Recurse -Include *.csproj,*.vcxproj -File
    foreach( $prjFile in $prjFiles )
    {
        Write-Host "  $($prjFile.FullName)"
        $project = Generate-ProjectInfo -prjFilePath $prjFile.FullName
        $projects += $project
    }
    return $projects
}

# vcxproj, csproj(.NET Framework), csproj(.NET Core) のプロジェクトファイルの参照チェックテスト用コード(通常は不要なので、コメントで残しておく)
# Generate-ProjectInfo -prjFilePath "C:\Projects\Morrin\IkinariPDF\v14\v14_Develop\Application\Auxiliary\WindowManageAuxiliary\WindowManageAuxiliary.vcxproj"
# Generate-ProjectInfo -prjFilePath "C:\Projects\Morrin\IkinariPDF\v14\v14_Develop\Application\DebuggingTools\ObjectCountTool\ObjectCountTool.csproj"
# Generate-ProjectInfo -prjFilePath "C:\Projects\Morrin\IkinariPDF\v14\v14_Develop\SupportTools\CopyFilesV2\CopyFiles.Extensions.UI.WPF\CopyFiles.Extensions.UI.WPF.csproj"
