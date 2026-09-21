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
	 * Extracts the engine assets normally exposed by OpenFL
	 * and, separately, extracts BFEXEOPT mods directly from
	 * the installed APK.
	 *
	 * Expected MT Manager layout:
	 *
	 * APK
	 * └── assets/
	 *     └── BFEXEOPT/
	 *         └── mods/
	 *             └── TestMod/
	 *
	 * Result:
	 *
	 * /storage/emulated/0/.BFEXEOPT/
	 * └── mods/
	 *     └── TestMod/
	 *
	 * The mod extraction does NOT depend on Assets.list().
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
				storageDir
			);

			ensureDirectory(
				storageDir + 'assets/'
			);

			ensureDirectory(
				storageDir + 'mods/'
			);

			/*
			 * -------------------------------------------------
			 * 1. Extract normal OpenFL/Lime engine assets
			 * -------------------------------------------------
			 */
			extractRegisteredAssets(
				storageDir
			);

			/*
			 * -------------------------------------------------
			 * 2. Extract BFEXEOPT directly from APK
			 * -------------------------------------------------
			 */
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

	/**
	 * Extracts the normal assets registered by OpenFL.
	 *
	 * This part is intentionally kept separate from the
	 * APK mod extraction.
	 */
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

				/*
				 * Do not process BFEXEOPT here.
				 *
				 * Mods are handled directly from the APK
				 * by extractModsFromAPK().
				 */
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

	/**
	 * Finds the installed APK path.
	 *
	 * Android's package manager returns something similar to:
	 *
	 * package:/data/app/....../base.apk
	 */
	private static function getInstalledAPKPath():String
	{
		try
		{
			var packageName:String =
				lime.app.Application.current.meta
					.get('packageName');

			if (
				packageName == null
				|| packageName.length == 0
			)
			{
				trace(
					'[StorageUtil] Package name unavailable.'
				);

				return '';
			}

			var process:Process =
				new Process(
					'pm path '
					+ packageName
				);

			var output:String =
				process.stdout
					.readAll()
					.toString();

			process.close();

			if (output == null)
				return '';

			for (line in output.split('\n'))
			{
				var clean:String =
					line.trim();

				if (
					clean.startsWith(
						'package:'
					)
				)
				{
					var apkPath:String =
						clean.substr(
							'package:'.length
						).trim();

					if (
						apkPath.length > 0
						&& FileSystem.exists(apkPath)
					)
					{
						return apkPath;
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Unable to find APK: '
				+ e
			);
		}

		return '';
	}

	/**
	 * Extracts only BFEXEOPT content from the installed APK.
	 *
	 * MT Manager target:
	 *
	 * assets/BFEXEOPT/mods/
	 *
	 * Temporary extraction:
	 *
	 * .BFEXEOPT/.apk_extract/
	 *
	 * Then the contents of BFEXEOPT/mods are copied to:
	 *
	 * .BFEXEOPT/mods/
	 */
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
				'[StorageUtil] Installed APK path not found.'
			);

			return;
		}

		trace(
			'[StorageUtil] APK detected: '
			+ apkPath
		);

		var temporaryDir:String =
			storageDir
			+ '.apk_extract/';

		try
		{
			/*
			 * Remove an old temporary extraction.
			 */
			if (FileSystem.exists(temporaryDir))
			{
				deleteDirectory(
					temporaryDir
				);
			}

			ensureDirectory(
				temporaryDir
			);

			/*
			 * Android APKs normally store application
			 * assets under the APK "assets/" directory.
			 *
			 * We specifically extract BFEXEOPT only.
			 */
			var command:String =
				'unzip -o '
				+ shellQuote(apkPath)
				+ ' "assets/BFEXEOPT/*"'
				+ ' -d '
				+ shellQuote(temporaryDir);

			trace(
				'[StorageUtil] Extracting BFEXEOPT from APK...'
			);

			var process:Process =
				new Process(
					command
				);

			var stdout:String =
				process.stdout
					.readAll()
					.toString();

			var stderr:String =
				process.stderr
					.readAll()
					.toString();

			var exitCode:Int =
				process.exitCode();

			process.close();

			if (stdout != null && stdout.length > 0)
			{
				trace(
					'[StorageUtil] unzip: '
					+ stdout
				);
			}

			if (stderr != null && stderr.length > 0)
			{
				trace(
					'[StorageUtil] unzip stderr: '
					+ stderr
				);
			}

			if (exitCode != 0)
			{
				trace(
					'[StorageUtil] unzip failed with exit code '
					+ exitCode
				);

				deleteDirectory(
					temporaryDir
				);

				return;
			}

			/*
			 * unzip produces:
			 *
			 * .apk_extract/assets/BFEXEOPT/
			 */
			var extractedRoot:String =
				Path.addTrailingSlash(
					temporaryDir
					+ 'assets/BFEXEOPT'
				);

			if (!FileSystem.exists(extractedRoot))
			{
				trace(
					'[StorageUtil] BFEXEOPT was not found '
					+ 'inside the APK.'
				);

				deleteDirectory(
					temporaryDir
				);

				return;
			}

			/*
			 * We only need the mods directory.
			 */
			var extractedMods:String =
				Path.addTrailingSlash(
					extractedRoot
					+ 'mods'
				);

			if (!FileSystem.exists(extractedMods))
			{
				trace(
					'[StorageUtil] No mods directory found '
					+ 'inside APK.'
				);

				deleteDirectory(
					temporaryDir
				);

				return;
			}

			var destinationMods:String =
				Path.addTrailingSlash(
					storageDir
					+ 'mods'
				);

			ensureDirectory(
				destinationMods
			);

			copyDirectoryContents(
				extractedMods,
				destinationMods
			);

			trace(
				'[StorageUtil] APK mod extraction complete.'
			);

			/*
			 * Temporary files are no longer needed.
			 */
			deleteDirectory(
				temporaryDir
			);
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] APK mod extraction failed: '
				+ e
			);

			try
			{
				if (FileSystem.exists(temporaryDir))
				{
					deleteDirectory(
						temporaryDir
					);
				}
			}
			catch (_:Dynamic)
			{
			}
		}
	}

	/**
	 * Copies a directory recursively.
	 */
	private static function copyDirectoryContents(
		sourceDirectory:String,
		destinationDirectory:String
	):Void
	{
		sourceDirectory =
			Path.addTrailingSlash(
				sourceDirectory
			);

		destinationDirectory =
			Path.addTrailingSlash(
				destinationDirectory
			);

		ensureDirectory(
			destinationDirectory
		);

		for (
			entry in FileSystem.readDirectory(
				sourceDirectory
			)
		)
		{
			var sourcePath:String =
				sourceDirectory + entry;

			var destinationPath:String =
				destinationDirectory + entry;

			if (
				FileSystem.isDirectory(
					sourcePath
				)
			)
			{
				copyDirectoryContents(
					sourcePath,
					destinationPath
				);
			}
			else
			{
				copyFileIfNeeded(
					sourcePath,
					destinationPath
				);
			}
		}
	}

	/**
	 * Copies one file only when necessary.
	 */
	private static function copyFileIfNeeded(
		sourcePath:String,
		destinationPath:String
	):Void
	{
		try
		{
			var sourceBytes:Bytes =
				File.getBytes(
					sourcePath
				);

			var shouldWrite:Bool = true;

			if (
				FileSystem.exists(
					destinationPath
				)
			)
			{
				try
				{
					var existingBytes:Bytes =
						File.getBytes(
							destinationPath
						);

					if (
						existingBytes.length
						== sourceBytes.length
						&& existingBytes.compare(
							sourceBytes
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
				return;

			var outputDirectory:String =
				Path.directory(
					destinationPath
				);

			ensureDirectory(
				outputDirectory
			);

			File.saveBytes(
				destinationPath,
				sourceBytes
			);

			trace(
				'[StorageUtil] Mod file: '
				+ sourcePath
				+ ' -> '
				+ destinationPath
			);
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Failed to copy file: '
				+ sourcePath
				+ ' (' + e + ')'
			);
		}
	}

	/**
	 * Deletes a directory recursively.
	 */
	private static function deleteDirectory(
		directory:String
	):Void
	{
		if (
			directory == null
			|| !FileSystem.exists(directory)
		)
		{
			return;
		}

		if (!FileSystem.isDirectory(directory))
		{
			try
			{
				FileSystem.deleteFile(
					directory
				);
			}
			catch (_:Dynamic)
			{
			}

			return;
		}

		for (
			entry in FileSystem.readDirectory(
				directory
			)
		)
		{
			var path:String =
				Path.addTrailingSlash(
					directory
				) + entry;

			if (FileSystem.isDirectory(path))
			{
				deleteDirectory(
					path
				);
			}
			else
			{
				try
				{
					FileSystem.deleteFile(
						path
					);
				}
				catch (_:Dynamic)
				{
				}
			}
		}

		try
		{
			FileSystem.deleteDirectory(
				directory
			);
		}
		catch (_:Dynamic)
		{
		}
	}

	/**
	 * Quotes a path for the Android shell.
	 */
	private static function shellQuote(
		value:String
	):String
	{
		if (value == null)
			return "''";

		return "'"
			+ value.split("'").join("'\\''")
			+ "'";
	}

	/**
	 * Extracts one OpenFL asset.
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
