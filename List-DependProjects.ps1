<#
.SYNOPSIS
    設定ファイルを読み取って、依存プロジェクトを列挙する

.DESCRIPTION
    このスクリプトは、指定された設定ファイルを読み取り、その設定に基づいて依存しているプロジェクトを列挙します。

.PARAMETER ConfigFilePath
    依存プロジェクトを列挙するための設定ファイルのパスを指定します。

.EXAMPLE
    Listup-DependProjects.ps1 -ConfigFilePath "C:\Projects\MyProject\Config\dependencies.json"
#>
# ISMの読み取りを行うサブルーチンを持ってくる(これだけでそれなりの規模になる)
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,HelpMessage="依存プロジェクトを列挙するための設定ファイルのパスを指定してください。")]
    $ConfigFilePath
)

# 設定ファイルを読み込む
$config = Get-Content $ConfigFilePath | ConvertFrom-Json

# MSBuild を呼び出すので最新バージョンを使えるようにして環境を構築する
. ".\Initialize-VsDevShell.ps1"
Initialize-VsDevShell -vsVersionMajor $config.VSVersion

# リポジトリ内のすべてのプロジェクトを列挙して、ビルド対象プロジェクトを絞り込む準備をする
. ".\Search-ProjectFiles.ps1"
. ".\Get-PlatformOutputPath.ps1"

# リポジトリ内のプロジェクトを列挙して検索対象プロジェクトの準備をする
Write-Host "リポジトリ内のプロジェクトを列挙中..."
$allProjects = Search-ProjectFiles -Root $config.Root

Write-Host "プロジェクト出力の取得中..."
$pathToProjects = @()
foreach( $project in $allProjects )
{
    Write-Host "$($project.Project) ..."
    $fullPath = Resolve-Path -RelativeBase $config.Root -Path $project.Project
    
    foreach( $platform in $project.Platforms )
    {
        $targetPath = Get-PlatformOutputPath -Root $config.Root -ProjectInfo $project -Platform $platform
        if( $null -ne $targetPath )
        {
            Write-Host "  Platform=$platform, TargetPath=$targetPath"
            $pathToProjects += [PSCustomObject]@{
                ProjectPath = $fullPath
                Platform = $platform
                TargetPath = $targetPath
            }
        }
    }
}

. ".\Read-IsmReferFiles.ps1"

# RemapPath はハッシュテーブルに変換する
$remapPath = @{}
foreach( $path in $config.RemapPaths )
{
    $remapPath[$path.Source] = $path.Destination
}
# リポジトリ($config.Root)内のすべてのプロジェクトを探す
$ismFilePath = Resolve-Path -RelativeBase $config.Root -Path $config.IsmFile

Write-Host "インストール対象ファイルを取得中..."
$referFiles = Read-IsmReferFiles -IsmFilePath $ismFilePath -RootPath $config.Root -remapPath $remapPath

# 再帰してプロジェクト参照を列挙する(サブルーチン)
$script:VisitedProjects = @()
function Dump-DependProject
{
    param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath,
        [Parameter(Mandatory=$true)]
        [string]$Platform,
        [Parameter(Mandatory=$true)]
        [int]$nestLevel
    )

    # すでに列挙済みのプロジェクトを保持して重複出力を抑制する
    $newProject = $true
    foreach( $visitedProject in $script:VisitedProjects )
    {
        if( $visitedProject.ProjectPath -eq $ProjectPath )
        {
            # 複数のプラットフォームを対象にビルドするプロジェクトもあるので、その場合は結合して、ネストレベルをより深いほうに合わせる
            if( $visitedProject.Platform -contains $Platform )
            {
                if( $visitedProject.NestLevel -lt $nestLevel )
                {
                    $visitedProject.NestLevel = $nestLevel
                }
                return
            }
            $visitedProject.Platform += ",$Platform"
            if( $visitedProject.NestLevel -lt $nestLevel )
            {
                $visitedProject.NestLevel = $nestLevel
            }
            $newProject = $false
            break
        }
    }
    if( $newProject )
    {
        $script:VisitedProjects += @{
            ProjectPath = $ProjectPath
            Platform = $Platform
            NestLevel = $nestLevel
        }
    }
    Write-Host "$ProjectPath (Platform: $Platform, NestLevel: $nestLevel)"

    [xml]$prj = Get-Content $ProjectPath
    # リファレンスプロジェクトをリストアップ
    $baseFolder = Split-Path -Parent $ProjectPath

    foreach( $prjRef in $prj.Project.ItemGroup.ProjectReference )
    {
        if( $null -ne $prjRef.Include )
        {
            $fullPath = Resolve-Path -RelativeBase $baseFolder -Path $prjRef.Include
            # C++とC#でプラットフォーム名が異なるので、両方探せるようにする
            $chkPlatform = @()
            $chkPlatform += $Platform
            if( $Platform -eq "x86" )
            {
                $chkPlatform += "Win32"
            }
            if( $Platform -eq "Win32" )
            {
                $chkPlatform += "x86"
            }
            if( $Platform -ne "AnyCPU" )
            {
                $chkPlatform += "AnyCPU"
            }
            # 依存するプロジェクトを列挙する
            $nextPrjPaths = $pathToProjects | Where-Object {
                [string]::Equals($_.ProjectPath, $fullPath, [System.StringComparison]::OrdinalIgnoreCase) -and $_.Platform -in $chkPlatform
            }
            foreach( $nextPrjPath in $nextPrjPaths )
            {
                Dump-DependProject -ProjectPath $nextPrjPath.ProjectPath -Platform $nextPrjPath.Platform -nestLevel ($nestLevel + 1)
            }
        }
    }
}

$topProjects = @()
Write-Host "ビルド対象プロジェクトの検索中..."
# 依存プロジェクトの参照ファイル一覧を出力する（ここまでの動作確認用）
foreach( $file in $referFiles )
{
    # 参照パス一覧から、exeプロジェクトの出力先をピックアップする(トップレベルプロジェクト扱い)
    $pathToProjects | Where-Object { $_.TargetPath -eq $file } | ForEach-Object {
        $topProjects += @{
            ProjectPath = $_.ProjectPath
            Platform = $_.Platform
        }
    }
}
# ビルド順を考慮する必要があるので
# $fullPath = Resolve-Path -RelativeBase $config.Root -Path $project.Project
# $targetPath = Get-PlatformOutputPath -Root $config.Root -ProjectInfo $project -Platform $platform
# $pathToProjects += [PSCustomObject]@{
#     ProjectPath = $fullPath
#     Platform = $platform
#     TargetPath = $targetPath
# }
foreach( $topProject in $topProjects )
{
    # 依存プロジェクトを列挙する
    Dump-DependProject -ProjectPath $topProject.ProjectPath -Platform $topProject.Platform -nestLevel 0
}

# 依存プロジェクトの一覧を出力する
Write-Host "ビルドプロジェクト一覧の出力中..."
$outputPath = Join-Path -Path $config.Root -ChildPath $config.OutputName
$buildProjects = @()
# より深いネストレベルのプロジェクトを先にビルドするようにリストを並べる必要がある
foreach( $visitedProject in $script:VisitedProjects | Sort-Object -Property NestLevel, ProjectPath -Descending )
{
    $relativePath = Resolve-Path -RelativeBase $config.Root -Path $visitedProject.ProjectPath -Relative
    $platforms = $visitedProject.Platform -split ","
    $buildProjects += [PSCustomObject]@{
        Project = $relativePath
        Type = [System.IO.Path]::GetExtension($visitedProject.ProjectPath)
        Configurations = ("Release","Debug") # ここでは固定値としておく
        Platforms = $platforms
        NestLevel = $visitedProject.NestLevel
    }
}
$buildProjects | ConvertTo-Json -Depth 5 | Set-Content $outputPath -Encoding UTF8
