[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,HelpMessage="依存プロジェクトを列挙するための設定ファイルのパスを指定してください。")]
    $ConfigFilePath
)


. ".\Search-ProjectFiles.ps1"
. ".\List-SolutionProjects.ps1"

$config = Get-Content -LiteralPath $ConfigFilePath | ConvertFrom-Json
$outputPath = Resolve-Path -RelativeBasePath $config.Root -Path $config.OutputName
$buildProjects = Get-Content -LiteralPath $outputPath | ConvertFrom-Json

$solutionFiles = Get-ChildItem -Path $config.Root -Filter *.sln -Recurse

# 存在するすべてのソリューションに含まれる *.*proj 類は除外する
$projects = @()
foreach( $solutionFile in $solutionFiles ){
    $projects += List-SolutionProjects -SolutionFilePath $solutionFile.FullName
}

$useProjects = @()
# 相対パスに修正
foreach( $project in $projects ){
    $relPath = Resolve-Path -RelativeBasePath $config.Root -Path $project.Path -Relative
    $useProjects += $relPath
}
# ビルドターゲットリストのプロジェクトを利用プロジェクトとしてピックアップ
foreach( $buildPrj in $buildProjects ){
    $relPath = Resolve-Path -RelativeBasePath $config.Root -Path $buildPrj.Project -Relative
    if( $useProjects -notcontains $relPath ){
        $useProjects += $relPath
    }
}
# リポジトリルートからすべてのプロじぇうとをリストアップ
$allProjects = Search-ProjectFiles $config.Root

$unrefProjects = @()
foreach( $prj in $allProjects ){
    $relPath = $prj.Project
    if( $useProjects -notcontains $relPath ){
        $unrefProjects += $relPath
    }
}
New-Item -ItemType Directory -Path ".\obj" -Force
Set-Content ".\obj\UnrefProjects.txt" -Value $unrefProjects -Encoding UTF8
