using System.Diagnostics;
using System.Text.Json;
using System.Xml;

Trace.Listeners.Add( new ConsoleTraceListener() );

if( args.Length == 0 )
{
	Trace.WriteLine( "ListupDependProjects <ism FilePath>" );
	return;
}
// ファイルが存在していてなおかつ、xml 形式でスタイルシートに is.xml を参照しているもののみ対象とする
List<string> targetFiles = new();
foreach( var arg in args )
{
	Trace.WriteLine( arg );
	if( IsIsmXml( arg ) )
	{
		var fullPath = Path.GetFullPath( arg );
		targetFiles.Add( fullPath );
	}
	else
	{
		Trace.WriteLine( $"対象外: {arg}" );
	}
}
// 対象ファイルの、参照ファイル一覧を取得する
HashSet<string> referFiles = new();
foreach( var ismPath in targetFiles )
{
	// フルパスでセットされているので、ディレクトリが出てこないということはない
	var baseDir = Path.GetDirectoryName( ismPath )!;
	var defineMapFilePath = Path.Combine( baseDir, "IsmDefineMap.json" );
	Dictionary<string, string>? remapPath = default;
	if( File.Exists( defineMapFilePath ) )
	{
		// ismの参照パスの物理パスを変換する際の事前パス変換テーブル(単純に一致したものを差し替えるだけの簡単なパスリスト)
		remapPath = await JsonSerializer.DeserializeAsync<Dictionary<string, string>>( File.OpenRead( defineMapFilePath ) );
	}
	// XMLとして改めてロードする
	XmlDocument ism = new();
	ism.Load( ismPath );
	// ISBuildSourcePath が参照ファイルなので、一式取り込んでフルパスに変換する
	ReadReferFiles( referFiles, ism, baseDir, remapPath ?? new() );
	foreach( var refFile in referFiles )
	{
		// 参照しているファイル一覧をリストアップ(ひとまず)
		Trace.WriteLine( refFile );
	}
}

// Sub-Routines
bool IsIsmXml( string xmlFilePath )
{
	Trace.WriteLine( $"CheckFile: {xmlFilePath}" );
	XmlDocument xmlDoc = new();
	try
	{
		// XMLとしてロードしてみる(失敗したらXMLではないので、無視)
		xmlDoc.Load( xmlFilePath );
		// 名前空間に dt があり、`urn:schemas-microsoft-com:datatypes` であることを確認する
		//var namespaceManager = new XmlNamespaceManager( xmlDoc.NameTable );
		var dtNamespace = xmlDoc.DocumentElement?.GetNamespaceOfPrefix( "dt" );
		if( dtNamespace != "urn:schemas-microsoft-com:datatypes" )
		{
			return false;
		}
	}
	// XML 形式ではない場合は無視でよい
	catch( XmlException )
	{
		return false;
	}
	return true;
}

// ISPathVariable テーブルを読み取ってパス変換できるようにする
Dictionary<string, string> ReadPathVariable( string projectFolder, XmlDocument ism )
{
	var pathVariable = new Dictionary<string, string>();
	var isPathVariables = ism.SelectNodes( "//table[@name='ISPathVariable']/row" );
	if( isPathVariables != null )
	{
		foreach( XmlElement row in isPathVariables )
		{
			if( row.ChildNodes.Count >= 2 )
			{
				var key = row.ChildNodes[0]?.InnerText;
				var value = row.ChildNodes[1]?.InnerText;
				if( key == "ISProjectFolder" )
				{
					value = projectFolder;
				}
				if( string.IsNullOrEmpty( key ) == false && string.IsNullOrEmpty( value ) == false )
				{
					// キーはあとで単純変換できるようにするために<>をつけておく
					pathVariable["<" + key + ">"] = value;
				}
			}
		}
	}
	return pathVariable;
}
int GetISBuildSourcePathIndex( XmlDocument ism, string? tableName )
{
	if( string.IsNullOrEmpty( tableName ) )
	{
		return -1;
	}
	var cols = ism.SelectNodes( $"//table[@name='{tableName}']/col" );
	if( cols == null )
	{
		return -1;
	}
	for( int index = 0 ; index < cols.Count ; index++ )
	{
		if( cols[index]?.InnerText == "ISBuildSourcePath" )
		{
			return index;
		}
	}
	return -1;
}
void ReadReferFiles( HashSet<string> referFiles, XmlDocument ism, string baseDir, Dictionary<string, string> remapPath )
{
	// ISPathVariable の変換テーブルを読み取る
	var pathVariable = ReadPathVariable( baseDir, ism );
	// ISBuildSourcePath の一覧を取得する
	var nodes = ism.SelectNodes( "//col[text()='ISBuildSourcePath']" );
	if( nodes == null )
	{
		return;
	}
	foreach( XmlElement node in nodes )
	{
		var tableName = node.ParentNode?.Attributes?["name"]?.Value;
		int index = GetISBuildSourcePathIndex( ism, tableName );
		if( index != -1 )
		{
			Trace.WriteLine( $"//table[@name='{tableName}']" );
			var rows = ism.SelectNodes( $"//table[@name='{tableName}']/row" );
			if( rows != null )
			{
				foreach( XmlElement row in rows )
				{
					var sourcePath = row.ChildNodes[index]?.InnerText;
					if( !string.IsNullOrEmpty( sourcePath ) )
					{
						// 無条件に変換しておけばよい
						foreach( var kv in remapPath )
						{
							sourcePath = sourcePath.Replace( kv.Key, kv.Value );
						}
						// パスは変換してから格納する(無駄なループは極力避けましょう)
						while( sourcePath.Contains( '<' ) )
						{
							bool isReplace = false;
							foreach( var kv in pathVariable )
							{
								var replacePath = sourcePath.Replace( kv.Key, kv.Value );
								// 変換したら再チェック(順番はわからないので)
								if( replacePath != sourcePath )
								{
									sourcePath = replacePath;
									isReplace = true;
									break;
								}
							}
							// 変換しなかった場合はループを抜ける
							if( !isReplace )
							{
								break;
							}
						}
						// どこかのパスとして変換された場合だけ格納する(<???>のままのものは無視
						if( !sourcePath.Contains( '<' ) )
						{
							// .ism より上位のフォルダを参照する可能性もあるので、正規化する
							sourcePath = Path.GetFullPath( sourcePath );
							referFiles.Add( sourcePath );
						}
					}
				}
			}
		}
	}
}
