package mobile.backend;

import lime.system.System as LimeSystem;
import lime.utils.Assets;
import haxe.io.Path;
import haxe.Exception;
import haxe.io.Bytes;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
#end

class StorageUtil
{
	#if sys
	public static final rootDir:String = LimeSystem.applicationStorageDirectory;

	public static function getStorageDirectory(?force:Bool = false):String
	{
		var daPath:String = '';

		#if android
		if (!FileSystem.exists(rootDir + 'storagetype.txt'))
			File.saveContent(rootDir + 'storagetype.txt', ClientPrefs.data.storageType);

		var curStorageType:String = File.getContent(rootDir + 'storagetype.txt').trim();

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

	public static function saveContent(fileName:String, fileData:String, ?alert:Bool = true):Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			File.saveContent('saves/$fileName', fileData);

			if (alert)
				CoolUtil.showPopUp('$fileName has been saved.', "Success!");
		}
		catch (e:Exception)
		{
			if (alert)
				CoolUtil.showPopUp(
					'$fileName couldn\'t be saved.\n(${e.message})',
					"Error!"
				);
		}
	}

	#if android

	public static function requestPermissions():Void
	{
		var mediaPermissions:Array<String> =
			AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU
			? [
				'READ_MEDIA_IMAGES',
				'READ_MEDIA_VIDEO',
				'READ_MEDIA_AUDIO'
			]
			: [
				'READ_EXTERNAL_STORAGE',
				'WRITE_EXTERNAL_STORAGE'
			];

		AndroidPermissions.requestPermissions(mediaPermissions);

		if (!AndroidEnvironment.isExternalStorageManager())
		{
			if (AndroidVersion.SDK_INT >= AndroidVersionCode.S)
				AndroidSettings.requestSetting('REQUEST_MANAGE_MEDIA');

			AndroidSettings.requestSetting(
				'MANAGE_APP_ALL_FILES_ACCESS_PERMISSION'
			);
		}

		var hasCorePermission:Bool =
			AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU
			? AndroidPermissions.getGrantedPermissions()
				.contains('android.permission.READ_MEDIA_IMAGES')
			: AndroidPermissions.getGrantedPermissions()
				.contains('android.permission.READ_EXTERNAL_STORAGE');

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
			var storageDir:String = StorageUtil.getStorageDirectory();

			if (!FileSystem.exists(storageDir))
				FileSystem.createDirectory(storageDir);
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
	 * Installs bundled BFEXEOPT mods into the normal
	 * .BFEXEOPT/mods/ directory.
	 *
	 * Source:
	 * BFEXEOPT/mods/...
	 *
	 * Destination:
	 * .BFEXEOPT/mods/...
	 */
	public static function extractBundledFiles():Void
	{
		try
		{
			var storageDir:String =
				Path.addTrailingSlash(getStorageDirectory());

			extractBFEXEOPTMods(storageDir);
		}
		catch (e:Dynamic)
		{
			trace('[StorageUtil] BFEXEOPT installation failed: ' + e);
		}
	}

	/**
	 * Finds only files inside:
	 *
	 * BFEXEOPT/mods/
	 *
	 * and copies them to:
	 *
	 * .BFEXEOPT/mods/
	 */
	private static function extractBFEXEOPTMods(storageDir:String):Void
	{
		var assetList:Array<String> = Assets.list();

		for (assetPath in assetList)
		{
			if (assetPath == null)
				continue;

			var normalized:String =
				assetPath.split('\\').join('/');

			// Only process BFEXEOPT/mods/
			if (!normalized.startsWith('BFEXEOPT/mods/'))
				continue;

			var relativePath:String =
				normalized.substr('BFEXEOPT/mods/'.length);

			if (relativePath.length == 0)
				continue;

			// Destination:
			// .BFEXEOPT/mods/...
			var outputPath:String =
				storageDir
				+ '.BFEXEOPT/'
				+ 'mods/'
				+ relativePath;

			var outputDirectory:String =
				Path.directory(outputPath);

			ensureDirectory(outputDirectory);

			try
			{
				var bytes:Bytes =
					Assets.getBytes(assetPath);

				if (bytes == null)
				{
					trace(
						'[StorageUtil] Unable to read: '
						+ assetPath
					);

					continue;
				}

				var shouldWrite:Bool = true;

				if (FileSystem.exists(outputPath))
				{
					try
					{
						var existingSize:Int =
							FileSystem.stat(outputPath).size;

						// Same size = don't rewrite it.
						if (existingSize == bytes.length)
							shouldWrite = false;
					}
					catch (e:Dynamic)
					{
						shouldWrite = true;
					}
				}

				if (shouldWrite)
				{
					File.saveBytes(outputPath, bytes);

					trace(
						'[StorageUtil] Installed: '
						+ relativePath
					);
				}
			}
			catch (e:Dynamic)
			{
				trace(
					'[StorageUtil] Failed: '
					+ assetPath
					+ ' -> '
					+ e
				);
			}
		}
	}

	/**
	 * Creates a directory and all missing parents.
	 */
	private static function ensureDirectory(directory:String):Void
	{
		if (directory == null || directory.length == 0)
			return;

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
			FileSystem.createDirectory(directory);
	}

	public static function checkExternalPaths(
		?splitStorage:Bool = false
	):Array<String>
	{
		var paths:Array<String> = [];

		try
		{
			var process = new Process(
				'grep -o "/storage/....-...." /proc/mounts | sort -u'
			);

			var output:String =
				process.stdout.readAll().toString();

			process.close();

			paths = output
				.split('\n')
				.filter(
					p -> p.trim().length > 0
				);

			if (splitStorage)
			{
				paths = paths.map(
					p -> p.replace('/storage/', '')
				);
			}
		}
		catch (e:Exception) {}

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
	final forcedPath = '/storage/emulated/0/';

	var EXTERNAL_DATA = "EXTERNAL_DATA";
	var EXTERNAL_OBB = "EXTERNAL_OBB";
	var EXTERNAL_MEDIA = "EXTERNAL_MEDIA";
	var EXTERNAL = "EXTERNAL";

	public static function fromStr(str:String):StorageType
	{
		var packageName:String =
			lime.app.Application.current.meta.get('packageName');

		var fileName:String =
			lime.app.Application.current.meta.get('file');

		return switch (str)
		{
			case "EXTERNAL_DATA":
				AndroidContext.getExternalFilesDir();

			case "EXTERNAL_OBB":
				AndroidContext.getObbDir();

			case "EXTERNAL_MEDIA":
				AndroidEnvironment.getExternalStorageDirectory()
					+ '/Android/media/'
					+ packageName;

			case "EXTERNAL":
				AndroidEnvironment.getExternalStorageDirectory()
					+ '/.'
					+ fileName;

			default:
				StorageUtil.getExternalDirectory(str)
					+ '.'
					+ fileName;
		}
	}

	public static function fromStrForce(str:String):StorageType
	{
		var packageName:String =
			lime.app.Application.current.meta.get('packageName');

		var fileName:String =
			lime.app.Application.current.meta.get('file');

		return switch (str)
		{
			case "EXTERNAL_DATA":
				forcedPath
					+ 'Android/data/'
					+ packageName
					+ '/files';

			case "EXTERNAL_OBB":
				forcedPath
					+ 'Android/obb/'
					+ packageName;

			case "EXTERNAL_MEDIA":
				forcedPath
					+ 'Android/media/'
					+ packageName;

			case "EXTERNAL":
				forcedPath
					+ '.'
					+ fileName;

			default:
				StorageUtil.getExternalDirectory(str)
					+ '.'
					+ fileName;
		}
	}
}

#end
