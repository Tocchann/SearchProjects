# ISMファイルでビルド時に参照するファイル一覧を取得する

function Read-PathVariable( $ism, $baseFolder )
{
    $pathVariable = @{}
    $ism.SelectNodes("//table[@name='ISPathVariable']/row") | ForEach-Object {
        if( $_.ChildNodes.Count -ge 2 )
        {
            $key = $_.ChildNodes[0]?.InnerText
            $value = $_.ChildNodes[1]?.InnerText
            if( $key -eq "ISProjectFolder" )
            {
                $value = $baseFolder
            }
            if( [string]::IsNullOrEmpty($key) -eq $false -and [string]::IsNullOrEmpty($value) -eq $false )
            {
                # キーはあとで単純変換できるようにするために<>をつけておく
                $pathVariable["<$key>"] = $value
            }
        }
    }
    return $pathVariable
}
function Get-ISBuildSourcePathIndex( $ism, $TableName )
{
    $retIndex = -1
    $cols = $ism.SelectNodes( "//table[@name='$TableName']/col" )
    for( $index = 0 ; $index -lt $cols.Count ; $index++ )
    {
        if( $cols[$index].InnerText -eq "ISBuildSourcePath" )
        {
            $retIndex = $index
            break
        }
    }
    return $retIndex
}


function Read-IsmReferFiles {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IsmFilePath,
        [Parameter(Mandatory=$true)]
        [string]$RootPath,
        [Parameter(Mandatory=$true)]
        [hashtable]$remapPath
    )
    [xml]$ism = Get-Content $IsmFilePath
    if( $ism.DocumentElement.GetNamespaceOfPrefix("dt") -ne "urn:schemas-microsoft-com:datatypes" )
    {
        throw "識別できる .ism ファイルではありません"
    }
    # <ISProjectFolder> の差し替えパスを取得する(.ismのある場所が基準点になっている)
    $baseFolder = Split-Path $IsmFilePath -Parent
    $pathVariable = Read-PathVariable $ism $baseFolder

    $files = @()
    $nodes = $ism.SelectNodes( "//col[text()='ISBuildSourcePath']" )
    foreach( $node in $nodes )
    {
        $tableName = $node.ParentNode?.Attributes?["name"]?.Value
        $index = Get-ISBuildSourcePathIndex $ism $tableName
        if( $index -eq -1 )
        {
            continue
        }
        $rows = $ism.SelectNodes( "//table[@name='$tableName']/row" )
        foreach( $row in $rows )
        {
            $sourcePath = $row.ChildNodes[$index]?.InnerText
            if( [string]::IsNullOrEmpty($sourcePath) )
            {
                continue
            }
            # 無条件に変換しておけばよい
            foreach( $kv in $remapPath.GetEnumerator() )
            {
                $sourcePath = $sourcePath.Replace( $kv.Key, $kv.Value )
            }
            while( $sourcePath.Contains( '<' ) )
            {
                $isReplace = $false
                foreach( $kv in $pathVariable.GetEnumerator() )
                {
                    $replacePath = $sourcePath.Replace( $kv.Key, $kv.Value )
                    # 変換したら再チェック(順番はわからないので)
                    if( $replacePath -ne $sourcePath )
                    {
                        $sourcePath = $replacePath
                        $isReplace = $true
                        break
                    }
                }
                # 変換しなかった場合はループを抜ける
                if( !$isReplace )
                {
                    break
                }
            }
            # どこかのパスとして変換された場合だけ格納する(<???>のままのものは無視)
            if( !$sourcePath.Contains('<') )
            {
                # .ism より上位のフォルダを参照する可能性もあるので、正規化する
                $sourcePath = [System.IO.Path]::GetFullPath( $sourcePath )
                $files += $sourcePath
            }
        }
    }
    return $files
}
