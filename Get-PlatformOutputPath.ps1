# 依存ファイルから、プロジェクトの出力先を指しているものを探す
# function Match-PlatformOutputPath( $Root, $ProjectInfo, $OutputPath )
# {
#     # プロジェクト設定(BuildTargetProjects.json)の情報をもとに出力パスと一致するものを探す(インストーラ相手なのでリリースプロジェクトのみ)
#     if( $ProjectInfo.Configurations -contains "Release" )
#     {
#         $projectPath = Resolve-Path -RelativeBase $Root -Path $ProjectInfo.Project
#         foreach( $platform in $ProjectInfo.Platforms ) {
#             $targetPath = MSBuild $projectPath -p:Configuration=Release -p:Platform=$platform -getProperty:TargetPath
#             if( $OutputPath.Equals($targetPath, [System.StringComparison]::OrdinalIgnoreCase) )
#             {
#                 return $platform
#             }
#         }
#     }
#     return $null
# }
function Get-PlatformOutputPath( $Root, $ProjectInfo, $Platform )
{
    if( $ProjectInfo.Configurations -contains "Release" -and
        $ProjectInfo.Platforms -contains $Platform )
    {
        $projectPath = Resolve-Path -RelativeBase $Root -Path $ProjectInfo.Project
        $targetPath = MSBuild $projectPath -p:Configuration=Release -p:Platform=$Platform -getProperty:TargetPath
        return $targetPath
    }
    return $null
}