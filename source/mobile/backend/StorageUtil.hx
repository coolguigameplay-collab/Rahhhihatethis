package mobile.backend;

import lime.system.System as LimeSystem;
import haxe.io.Path;
import haxe.io.Bytes;
import haxe.zip.Reader;
import haxe.zip.Entry;
import openfl.utils.Assets;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

class StorageUtil
{
	#if sys

	public static final rootDir:String =
		LimeSystem.applicationStorageDirectory;

	public static function getStorageDirectory(
		?force:Bool = false
	):String
	{
		var daPath:String = '';

		#if android

		if (!FileSystem.exists(rootDir + 'storagetype.txt'))
		{
			File.saveContent(
				rootDir + 'storagetype.txt',
				ClientPrefs.data.storageType
			);
		}

		var curStorageType:String =
			File.getContent(
				rootDir + 'storagetype.txt'
			).trim();

		daPath = force
			? StorageType.fromStrForce(curStorageType)
			: StorageType.fromStr(curStorageType);

		daPath = Path.addTrailingSlash(daPath);

		#elseif ios

		daPath = LimeSystem.documentsDirectory;

		#else

		daPath = Sys.getCwd();

		#end

		return daPath;
	}

	public static function saveContent(
		fileName:String,
		fileData:String,
		?alert:Bool = true
	):Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			File.saveContent(
				'saves/$fileName',
				fileData
			);

			if (alert)
			{
				CoolUtil.showPopUp(
					'$fileName has been saved.',
					'Success!'
				);
			}
		}
		catch (e:Dynamic)
		{
			if (alert)
			{
				CoolUtil.showPopUp(
					'$fileName couldn\'t be saved.\n(${e})',
					'Error!'
				);
			}
		}
	}

	#if android

	public static function requestPermissions():Void
	{
		var mediaPermissions:Array<String> =
			AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU
			?
			[
				'READ_MEDIA_IMAGES',
				'READ_MEDIA_VIDEO',
				'READ_MEDIA_AUDIO'
			]
			:
			[
				'READ_EXTERNAL_STORAGE',
				'WRITE_EXTERNAL_STORAGE'
			];

		AndroidPermissions.requestPermissions(
			mediaPermissions
		);

		if (!AndroidEnvironment.isExternalStorageManager())
		{
			if (AndroidVersion.SDK_INT >= AndroidVersionCode.S)
			{
				AndroidSettings.requestSetting(
					'REQUEST_MANAGE_MEDIA'
				);
			}

			AndroidSettings.requestSetting(
				'MANAGE_APP_ALL_FILES_ACCESS_PERMISSION'
			);
		}

		var hasCorePermission:Bool =
			AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU
			?
			AndroidPermissions
				.getGrantedPermissions()
				.contains(
					'android.permission.READ_MEDIA_IMAGES'
				)
			:
			AndroidPermissions
				.getGrantedPermissions()
				.contains(
					'android.permission.READ_EXTERNAL_STORAGE'
				);

		if (!hasCorePermission)
		{
			CoolUtil.showPopUp(
				'If you accepted the permissions you are all good!'
				+ '\nIf you didn\'t then expect a crash'
				+ '\nPress OK to see what happens',
				'Notice!'
			);
		}

		try
		{
			var storageDir:String =
				StorageUtil.getStorageDirectory();

			ensureDirectory(storageDir);
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp(
				'Please create directory to\n'
				+ StorageUtil.getStorageDirectory(true)
				+ '\nPress OK to close the game',
				'Error!'
			);

			LimeSystem.exit(1);
		}
	}

	public static function extractBundledFiles():Void
	{
		try
		{
			var storageDir:String =
				Path.addTrailingSlash(
					getStorageDirectory()
				);

			ensureDirectory(storageDir);
			ensureDirectory(storageDir + 'assets/');
			ensureDirectory(storageDir + 'mods/');

			extractRegisteredAssets(
				storageDir
			);

			extractModsFromAPK(
				storageDir
			);
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Extraction failed: '
				+ e
			);
		}
	}

	private static function extractRegisteredAssets(
		storageDir:String
	):Void
	{
		try
		{
			var assetList:Array<String> =
				Assets.list();

			if (assetList == null)
			{
				trace(
					'[StorageUtil] Assets.list() returned null.'
				);

				return;
			}

			var extracted:Int = 0;
			var failed:Int = 0;

			trace(
				'[StorageUtil] Found '
				+ assetList.length
				+ ' registered assets.'
			);

			for (assetPath in assetList)
			{
				if (assetPath == null)
					continue;

				var normalized:String =
					normalizeAssetPath(
						assetPath
					);

				if (normalized.length == 0)
					continue;

				if (
					normalized == 'BFEXEOPT'
					|| normalized.startsWith('BFEXEOPT/')
				)
				{
					continue;
				}

				var relativeAssetPath:String =
					normalized;

				if (
					relativeAssetPath.startsWith(
						'assets/'
					)
				)
				{
					relativeAssetPath =
						relativeAssetPath.substr(
							'assets/'.length
						);
				}

				if (relativeAssetPath.length == 0)
					continue;

				var outputPath:String =
					storageDir
					+ 'assets/'
					+ relativeAssetPath;

				if (
					extractSingleAsset(
						assetPath,
						normalized,
						outputPath
					)
				)
				{
					extracted++;
				}
				else
				{
					failed++;
				}
			}

			trace(
				'[StorageUtil] Engine asset extraction complete.'
				+ ' Extracted/updated: '
				+ extracted
				+ ' | Failed: '
				+ failed
			);
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Engine asset extraction failed: '
				+ e
			);
		}
	}

	private static function getInstalledAPKPath():String
	{
		try
		{
			#if android

			var packageCodePath:Dynamic =
				lime.app.Application.current.meta
					.get('packageCodePath');

			if (
				packageCodePath != null
				&& Std.string(packageCodePath).length > 0
			)
			{
				var candidate:String =
					Std.string(packageCodePath);

				if (FileSystem.exists(candidate))
					return candidate;
			}

			var apkMeta:Dynamic =
				lime.app.Application.current.meta
					.get('apkPath');

			if (
				apkMeta != null
				&& Std.string(apkMeta).length > 0
			)
			{
				var candidate:String =
					Std.string(apkMeta);

				if (FileSystem.exists(candidate))
					return candidate;
			}

			trace(
				'[StorageUtil] APK path metadata unavailable.'
			);

			return '';

			#else

			return '';

			#end
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Unable to get APK path: '
				+ e
			);

			return '';
		}
	}

	private static function extractModsFromAPK(
		storageDir:String
	):Void
	{
		var apkPath:String =
			getInstalledAPKPath();

		if (
			apkPath == null
			|| apkPath.length == 0
		)
		{
			trace(
				'[StorageUtil] Installed APK path not available.'
			);

			return;
		}

		if (!FileSystem.exists(apkPath))
		{
			trace(
				'[StorageUtil] APK does not exist: '
				+ apkPath
			);

			return;
		}

		trace(
			'[StorageUtil] Reading APK ZIP: '
			+ apkPath
		);

		var input:sys.io.FileInput = null;

		try
		{
			input =
				File.read(
					apkPath,
					true
				);

			var reader:Reader =
				new Reader(input);

			var entries:List<Entry> =
				reader.read();

			// IMPORTANT:
			// The APK contains BFEXEOPT directly at the APK root.
			// Example:
			// BFEXEOPT/mods/NamaMod/TEST.txt
			var prefix:String =
				'BFEXEOPT/mods/';

			var found:Int = 0;
			var extracted:Int = 0;
			var failed:Int = 0;

			for (entry in entries)
			{
				if (entry == null)
					continue;

				var entryName:String =
					entry.fileName;

				if (entryName == null)
					continue;

				entryName =
					entryName.split('\\').join('/');

				if (!entryName.startsWith(prefix))
					continue;

				if (entryName == prefix)
					continue;

				if (entryName.endsWith('/'))
					continue;

				found++;

				var relativePath:String =
					entryName.substr(
						prefix.length
					);

				if (relativePath.length == 0)
					continue;

				if (
					relativePath.startsWith('../')
					|| relativePath.contains('/../')
					|| relativePath == '..'
				)
				{
					trace(
						'[StorageUtil] Ignoring unsafe APK path: '
						+ entryName
					);

					continue;
				}

				var outputPath:String =
					Path.addTrailingSlash(
						storageDir + 'mods'
					)
					+ relativePath;

				try
				{
					var bytes:Bytes =
						Reader.unzip(entry);

					if (bytes == null)
					{
						failed++;

						trace(
							'[StorageUtil] Failed to unzip: '
							+ entryName
						);

						continue;
					}

					var outputDirectory:String =
						Path.directory(
							outputPath
						);

					ensureDirectory(
						outputDirectory
					);

					var shouldWrite:Bool = true;

					if (
						FileSystem.exists(
							outputPath
						)
					)
					{
						try
						{
							var existingBytes:Bytes =
								File.getBytes(
									outputPath
								);

							if (
								existingBytes.length
								== bytes.length
								&& existingBytes.compare(
									bytes
								) == 0
							)
							{
								shouldWrite = false;
							}
						}
						catch (e:Dynamic)
						{
							shouldWrite = true;
						}
					}

					if (shouldWrite)
					{
						File.saveBytes(
							outputPath,
							bytes
						);

						extracted++;

						trace(
							'[StorageUtil] APK mod: '
							+ entryName
							+ ' -> '
							+ outputPath
						);
					}
					else
					{
						extracted++;
					}
				}
				catch (e:Dynamic)
				{
					failed++;

					trace(
						'[StorageUtil] Failed to extract APK entry: '
						+ entryName
						+ ' (' + e + ')'
					);
				}
			}

			trace(
				'[StorageUtil] APK mod extraction complete.'
				+ ' Found: '
				+ found
				+ ' | Extracted/updated: '
				+ extracted
				+ ' | Failed: '
				+ failed
			);
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] APK ZIP reading failed: '
				+ e
			);
		}

		if (input != null)
		{
			try
			{
				input.close();
			}
			catch (e:Dynamic)
			{
			}
		}
	}

	private static function extractSingleAsset(
		assetPath:String,
		normalized:String,
		outputPath:String
	):Bool
	{
		try
		{
			var bytes:Bytes =
				Assets.getBytes(
					assetPath
				);

			if (bytes == null)
			{
				trace(
					'[StorageUtil] Unable to read asset: '
					+ normalized
				);

				return false;
			}

			var outputDirectory:String =
				Path.directory(
					outputPath
				);

			ensureDirectory(
				outputDirectory
			);

			var shouldWrite:Bool = true;

			if (
				FileSystem.exists(
					outputPath
				)
			)
			{
				try
				{
					var existingBytes:Bytes =
						File.getBytes(
							outputPath
						);

					if (
						existingBytes.length
						== bytes.length
						&& existingBytes.compare(
							bytes
						) == 0
					)
					{
						shouldWrite = false;
					}
				}
				catch (e:Dynamic)
				{
					shouldWrite = true;
				}
			}

			if (!shouldWrite)
				return true;

			File.saveBytes(
				outputPath,
				bytes
			);

			trace(
				'[StorageUtil] Extracted: '
				+ normalized
				+ ' -> '
				+ outputPath
			);

			return true;
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Failed to extract: '
				+ normalized
				+ ' (' + e + ')'
			);

			return false;
		}
	}

	private static function normalizeAssetPath(
		assetPath:String
	):String
	{
		var normalized:String =
			assetPath.split('\\').join('/');

		while (normalized.startsWith('./'))
		{
			normalized =
				normalized.substr(2);
		}

		while (normalized.startsWith('/'))
		{
			normalized =
				normalized.substr(1);
		}

		return normalized;
	}

	private static function ensureDirectory(
		directory:String
	):Void
	{
		if (
			directory == null
			|| directory.length == 0
		)
		{
			return;
		}

		if (FileSystem.exists(directory))
			return;

		var parent:String =
			Path.directory(
				directory
			);

		if (
			parent != directory
			&& parent.length > 0
			&& !FileSystem.exists(parent)
		)
		{
			ensureDirectory(
				parent
			);
		}

		if (!FileSystem.exists(directory))
		{
			FileSystem.createDirectory(
				directory
			);
		}
	}

	public static function checkExternalPaths(
		?splitStorage:Bool = false
	):Array<String>
	{
		var paths:Array<String> = [];

		return paths;
	}

	public static function getExternalDirectory(
		externalDir:String
	):String
	{
		var daPath:String = '';

		for (path in checkExternalPaths())
		{
			if (path.contains(externalDir))
				daPath = path;
		}

		return Path.addTrailingSlash(
			daPath.trim()
		);
	}

	#end
	#end
}

#if android

@:runtimeValue
enum abstract StorageType(String) from String to String
{
	final forcedPath =
		'/storage/emulated/0/';

	var EXTERNAL_DATA =
		'EXTERNAL_DATA';

	var EXTERNAL_OBB =
		'EXTERNAL_OBB';

	var EXTERNAL_MEDIA =
		'EXTERNAL_MEDIA';

	var EXTERNAL =
		'EXTERNAL';

	public static function fromStr(
		str:String
	):StorageType
	{
		var packageName:String =
			lime.app.Application.current.meta
				.get('packageName');

		var fileName:String =
			lime.app.Application.current.meta
				.get('file');

		return switch (str)
		{
			case 'EXTERNAL_DATA':
				AndroidContext.getExternalFilesDir();

			case 'EXTERNAL_OBB':
				AndroidContext.getObbDir();

			case 'EXTERNAL_MEDIA':
				AndroidEnvironment
					.getExternalStorageDirectory()
					+ '/Android/media/'
					+ packageName;

			case 'EXTERNAL':
				AndroidEnvironment
					.getExternalStorageDirectory()
					+ '/.'
					+ fileName;

			default:
				StorageUtil
					.getExternalDirectory(str)
					+ '.'
					+ fileName;
		};
	}

	public static function fromStrForce(
		str:String
	):StorageType
	{
		var packageName:String =
			lime.app.Application.current.meta
				.get('packageName');

		var fileName:String =
			lime.app.Application.current.meta
				.get('file');

		return switch (str)
		{
			case 'EXTERNAL_DATA':
				forcedPath
					+ 'Android/data/'
					+ packageName
					+ '/files';

			case 'EXTERNAL_OBB':
				forcedPath
					+ 'Android/obb/'
					+ packageName;

			case 'EXTERNAL_MEDIA':
				forcedPath
					+ 'Android/media/'
					+ packageName;

			case 'EXTERNAL':
				forcedPath
					+ '.'
					+ fileName;

			default:
				StorageUtil
					.getExternalDirectory(str)
					+ '.'
					+ fileName;
		};
	}
}

#end
