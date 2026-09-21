package mobile.backend;

import lime.system.System as LimeSystem;
import haxe.io.Path;
import haxe.Exception;
import haxe.io.Bytes;
import openfl.utils.Assets;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
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
		catch (e:Exception)
		{
			if (alert)
			{
				CoolUtil.showPopUp(
					'$fileName couldn\'t be saved.\n(${e.message})',
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

	/**
	 * Extracts all embedded assets that are visible through
	 * the OpenFL asset system.
	 *
	 * Engine assets:
	 *     .BFEXEOPT/assets/...
	 *
	 * Bundled mods:
	 *     .BFEXEOPT/mods/...
	 *
	 * The extraction is based on Assets.list(), but unlike
	 * the previous version it does NOT require engine assets
	 * to literally start with "assets/".
	 */
	public static function extractBundledFiles():Void
	{
		try
		{
			var storageDir:String =
				Path.addTrailingSlash(
					getStorageDirectory()
				);

			ensureDirectory(
				storageDir + 'assets/'
			);

			ensureDirectory(
				storageDir + 'mods/'
			);

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
			var skipped:Int = 0;
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
					normalizeAssetPath(assetPath);

				if (normalized.length == 0)
					continue;

				/*
				 * BFEXEOPT bundled content.
				 *
				 * Example:
				 *
				 * BFEXEOPT/mods/TestMod/test.txt
				 *
				 * becomes:
				 *
				 * .BFEXEOPT/mods/TestMod/test.txt
				 */
				if (normalized == 'BFEXEOPT'
					|| normalized.startsWith('BFEXEOPT/'))
				{
					var relativeModPath:String =
						normalized == 'BFEXEOPT'
						? ''
						: normalized.substr(
							'BFEXEOPT/'.length
						);

					if (relativeModPath.length == 0)
						continue;

					var modOutputPath:String =
						storageDir
						+ relativeModPath;

					if (extractSingleAsset(
						assetPath,
						normalized,
						modOutputPath
					))
					{
						extracted++;
					}
					else
					{
						failed++;
					}

					continue;
				}

				/*
				 * Everything else exposed by OpenFL's
				 * asset system is treated as an engine
				 * asset and placed under:
				 *
				 * .BFEXEOPT/assets/
				 *
				 * If the asset already begins with
				 * "assets/", that prefix is preserved.
				 *
				 * Otherwise we add it.
				 */
				var relativeAssetPath:String =
					normalized;

				if (relativeAssetPath.startsWith('assets/'))
				{
					relativeAssetPath =
						relativeAssetPath.substr(
							'assets/'.length
						);
				}

				if (relativeAssetPath.length == 0)
					continue;

				var assetOutputPath:String =
					storageDir
					+ 'assets/'
					+ relativeAssetPath;

				if (extractSingleAsset(
					assetPath,
					normalized,
					assetOutputPath
				))
				{
					extracted++;
				}
				else
				{
					failed++;
				}
			}

			trace(
				'[StorageUtil] Extraction complete.'
				+ ' Extracted/updated: '
				+ extracted
				+ ' | Failed: '
				+ failed
				+ ' | Registered: '
				+ assetList.length
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

	/**
	 * Extracts one asset from OpenFL's asset system.
	 */
	private static function extractSingleAsset(
		assetPath:String,
		normalized:String,
		outputPath:String
	):Bool
	{
		try
		{
			var bytes:Bytes =
				Assets.getBytes(assetPath);

			if (bytes == null)
			{
				trace(
					'[StorageUtil] Unable to read asset: '
					+ normalized
				);

				return false;
			}

			var outputDirectory:String =
				Path.directory(outputPath);

			ensureDirectory(
				outputDirectory
			);

			/*
			 * Always compare the actual contents when
			 * a file already exists.
			 *
			 * This avoids the old situation where two
			 * different files with the same size were
			 * incorrectly considered identical.
			 */
			var shouldWrite:Bool = true;

			if (FileSystem.exists(outputPath))
			{
				try
				{
					var existingBytes:Bytes =
						File.getBytes(outputPath);

					if (existingBytes.length == bytes.length
						&& existingBytes.compare(bytes) == 0)
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
			{
				return true;
			}

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

	/**
	 * Normalizes asset paths returned by OpenFL.
	 */
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
		if (directory == null
			|| directory.length == 0)
		{
			return;
		}

		if (FileSystem.exists(directory))
			return;

		var parent:String =
			Path.directory(directory);

		if (
			parent != directory
			&& parent.length > 0
			&& !FileSystem.exists(parent)
		)
		{
			ensureDirectory(parent);
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

		try
		{
			var process =
				new Process(
					'grep -o "/storage/....-...." /proc/mounts | sort -u'
				);

			var output:String =
				process.stdout
					.readAll()
					.toString();

			process.close();

			paths =
				output
					.split('\n')
					.filter(
						p -> p.trim().length > 0
					);

			if (splitStorage)
			{
				paths =
					paths.map(
						p -> p.replace(
							'/storage/',
							''
						)
					);
			}
		}
		catch (e:Exception)
		{
		}

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
