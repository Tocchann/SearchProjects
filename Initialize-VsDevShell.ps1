# 実行中の PowerShell のVS環境を指定バージョンに設定する(モジュールは最新版を使う)
function Initialize-VsDevShell([Parameter(Mandatory=$true)][int]$vsVersionMajor) {
    $needLatest = $false
    if ($vsVersionMajor -lt 1) {
        $needLatest = $true
    }
    $vsVerNext = $vsVersionMajor + 1

    $vswherePath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio" "Installer" "vswhere.exe"
    if (-not (Test-Path $vswherePath)) {
        Write-Error "vswhere.exeが見つかりません。Visual Studio(Ver=$vsVersionMajor) をインストールしてください"
        exit 1
    }

    $installPath = . $vswherePath -latest -property installationPath
    if (-not $installPath) {
        Write-Error "指定されたバージョンのVS(Ver=$vsVersionMajor)がインストールされていません。"
        exit 1
    }

    if ($needLatest) {
        $instanceId = . $vswherePath -latest -property instanceId
    }
    else {
        $instanceId = . $vswherePath -version "[$vsVersionMajor.0,$vsVerNext.0)" -property instanceId
    }

    $importedModule = Get-Module -Name "Microsoft.VisualStudio.DevShell"
    if (!$importedModule) {
        # 新たなモジュールをロードする(差し替えはうまくいかないっぽい…)
        $vsDevShell = Join-Path $installPath "Common7" "Tools" "Microsoft.VisualStudio.DevShell.dll"
        Import-Module $vsDevShell
    }
    
    if ($vsVersionMajor -ge 17) {
        # VS2022 からはホストアーキテクチャを指定してやらないと安定しないようだ(x64以外で動かす予定はないので常にamd64で指定する)
        Enter-VsDevShell -VsInstanceId $instanceId -Arch amd64 -HostArch amd64 -SkipAutomaticLocation 
    }
    else {
        Enter-VsDevShell -VsInstanceId $instanceId -SkipAutomaticLocation 
    }
}
