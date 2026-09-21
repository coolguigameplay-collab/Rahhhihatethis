package mobile.backend;

import lime.system.System as LimeSystem;
#if android
import lime.system.JNI;
#end

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

	/**
	 * ============================================================
	 * MAIN EXTRACTION
	 * ============================================================
	 *
	 * Extracts:
	 *
	 * 1. Normal OpenFL engine assets
	 *
	 * 2. Mods directly from the installed APK.
	 *
	 * APK structure:
	 *
	 * BFEXEOPT/
	 * └── mods/
	 *     ├── BikiniHorrors/
	 *     │   └── ...
	 *     ├── AnotherMod/
	 *     │   └── ...
	 *     └── ...
	 *
	 * External structure:
	 *
	 * /storage/emulated/0/.BFEXEOPT/
	 * ├── assets/
	 * └── mods/
	 *     ├── BikiniHorrors/
	 *     └── AnotherMod/
	 *
	 * IMPORTANT:
	 *
	 * The mod does NOT need to be registered in Assets.list().
	 *
	 * Therefore a mod inserted into the APK AFTER BUILD
	 * using MT Manager can still be extracted.
	 */
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

			/*
			 * Normal engine assets.
			 *
			 * This still uses OpenFL's asset system.
			 */
			extractRegisteredAssets(
				storageDir
			);

			/*
			 * IMPORTANT:
			 *
			 * Mods are NOT read from Assets.list().
			 *
			 * They are read directly from the installed APK.
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
	 * ============================================================
	 * NORMAL ENGINE ASSETS
	 * ============================================================
	 *
	 * Extracts normal OpenFL assets to:
	 *
	 * .BFEXEOPT/assets/
	 *
	 * BFEXEOPT/mods/ is intentionally ignored here.
	 *
	 * Mods are handled separately by extractModsFromAPK().
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
				 * Mods are handled directly from APK.
				 */
				if (
					normalized.startsWith(
						'BFEXEOPT/mods/'
					)
				)
				{
					continue;
				}

				/*
				 * Ignore other files inside BFEXEOPT.
				 */
				if (
					normalized == 'BFEXEOPT'
					|| normalized.startsWith(
						'BFEXEOPT/'
					)
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
				'[StorageUtil] Asset extraction failed: '
				+ e
			);
		}
	}

	/**
	 * ============================================================
	 * GET INSTALLED APK PATH
	 * ============================================================
	 *
	 * Android does not expose the APK path through
	 * Lime Application.meta.
	 *
	 * We obtain the running Application Context through:
	 *
	 * android.app.ActivityThread.currentApplication()
	 *
	 * and then call:
	 *
	 * Context.getPackageCodePath()
	 *
	 * Example result:
	 *
	 * /data/app/~~xxxxx==/com.bfexeopt.engine-xxxxx==/base.apk
	 *
	 * This is the actual APK that Android is running.
	 */
	private static function getInstalledAPKPath():String
	{
		try
		{
			/*
			 * ActivityThread.currentApplication()
			 *
			 * ()Landroid/app/Application;
			 */
			var getApplication:Dynamic =
				JNI.createStaticMethod(
					'android/app/ActivityThread',
					'currentApplication',
					'()Landroid/app/Application;',
					false,
					true
				);

			if (getApplication == null)
			{
				trace(
					'[StorageUtil] Unable to create currentApplication JNI method.'
				);

				return '';
			}

			var application:Dynamic =
				getApplication();

			if (application == null)
			{
				trace(
					'[StorageUtil] currentApplication() returned null.'
				);

				return '';
			}

			/*
			 * Context.getPackageCodePath()
			 *
			 * ()Ljava/lang/String;
			 */
			var getPackageCodePath:Dynamic =
				JNI.createMemberMethod(
					'android/content/Context',
					'getPackageCodePath',
					'()Ljava/lang/String;',
					false,
					true
				);

			if (getPackageCodePath == null)
			{
				trace(
					'[StorageUtil] Unable to create getPackageCodePath JNI method.'
				);

				return '';
			}

			var apkPath:Dynamic =
				getPackageCodePath(
					application
				);

			if (apkPath == null)
			{
				trace(
					'[StorageUtil] getPackageCodePath() returned null.'
				);

				return '';
			}

			var result:String =
				Std.string(apkPath);

			if (
				result.length == 0
				|| !FileSystem.exists(result)
			)
			{
				trace(
					'[StorageUtil] APK path does not exist: '
					+ result
				);

				return '';
			}

			trace(
				'[StorageUtil] Installed APK: '
				+ result
			);

			return result;
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Failed to get installed APK path: '
				+ e
			);

			return '';
		}
	}

	/**
	 * ============================================================
	 * EXTRACT MODS DIRECTLY FROM APK
	 * ============================================================
	 *
	 * Reads the APK as a ZIP archive.
	 *
	 * This is the important part that allows:
	 *
	 * Build APK
	 *      ↓
	 * MT Manager
	 *      ↓
	 * Insert BFEXEOPT/mods/MyMod/
	 *      ↓
	 * Repack APK
	 *      ↓
	 * Install
	 *      ↓
	 * Game reads MyMod directly from APK
	 *
	 * Assets.list() is NOT involved here.
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
				'[StorageUtil] Cannot extract mods: APK path unavailable.'
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

		var input:sys.io.FileInput;

		try
		{
			input =
				File.read(
					apkPath,
					true
				);
		}
		catch (e:Dynamic)
		{
			trace(
				'[StorageUtil] Failed to open APK: '
				+ e
			);

			return;
		}

		try
		{
			var reader:Reader =
				new Reader(input);

			var entries:Array<Entry> =
				reader.read();

			var prefix:String =
				'BFEXEOPT/mods/';

			var extracted:Int = 0;
			var skipped:Int = 0;
			var failed:Int = 0;

			trace(
				'[StorageUtil] Reading APK directly.'
			);

			trace(
				'[StorageUtil] ZIP entries: '
				+ entries.length
			);

			for (entry in entries)
			{
				if (entry == null)
					continue;

				var entryName:String =
					normalizeAssetPath(
						entry.fileName
					);

				/*
				 * We only care about:
				 *
				 * BFEXEOPT/mods/...
				 */
				if (
					!entryName.startsWith(
						prefix
					)
				)
				{
					continue;
				}

				var relativePath:String =
					entryName.substr(
						prefix.length
					);

				if (relativePath.length == 0)
					continue;

				/*
				 * Ignore directory entries.
				 *
				 * Most APK ZIP directory entries end with '/'.
				 */
				if (
					entryName.endsWith('/')
					|| relativePath.endsWith('/')
				)
				{
					continue;
				}

				/*
				 * Security:
				 *
				 * Never allow:
				 *
				 * ../
				 * absolute paths
				 * paths escaping mods/
				 */
				if (
					!isSafeRelativePath(
						relativePath
					)
				)
				{
					trace(
						'[StorageUtil] Unsafe APK path skipped: '
						+ entryName
					);

					skipped++;
					continue;
				}

				var outputPath:String =
					storageDir
					+ 'mods/'
					+ relativePath;

				try
				{
					var bytes:Bytes =
						Reader.unzip(
							entry
						);

					if (bytes == null)
					{
						trace(
							'[StorageUtil] Unable to unzip: '
							+ entryName
						);

						failed++;
						continue;
					}

					var outputDirectory:String =
						Path.directory(
							outputPath
						);

					ensureDirectory(
						outputDirectory
					);

					var shouldWrite:Bool =
						true;

					/*
					 * Do not rewrite identical files.
					 */
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
						catch (compareError:Dynamic)
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

						trace(
							'[StorageUtil] MOD extracted: '
							+ entryName
							+ ' -> '
							+ outputPath
						);
					}
					else
					{
						trace(
							'[StorageUtil] MOD already up to date: '
							+ relativePath
						);
					}

					extracted++;
				}
				catch (e:Dynamic)
				{
					trace(
						'[StorageUtil] Failed MOD entry: '
						+ entryName
						+ ' (' + e + ')'
					);

					failed++;
				}
			}

			trace(
				'[StorageUtil] APK mod extraction complete.'
				+ ' Processed: '
				+ extracted
				+ ' | Skipped: '
				+ skipped
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
		finally
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

	/**
	 * ============================================================
	 * APK PATH SECURITY
	 * ============================================================
	 */
	private static function isSafeRelativePath(
		path:String
	):Bool
	{
		if (
			path == null
			|| path.length == 0
		)
		{
			return false;
		}

		var normalized:String =
			path.split('\\').join('/');

		while (normalized.startsWith('/'))
		{
			normalized =
				normalized.substr(1);
		}

		if (
			normalized.length == 0
			|| normalized.startsWith('../')
			|| normalized.contains('/../')
			|| normalized == '..'
			|| normalized.contains(':')
		)
		{
			return false;
		}

		return true;
	}

	/**
	 * ============================================================
	 * OPENFL ASSET EXTRACTION
	 * ============================================================
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
			{
				trace(
					'[StorageUtil] Already up to date: '
					+ normalized
				);

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
				'[StorageUtil] Failed to extract '
				+ normalized
				+ ' (' + e + ')'
			);

			return false;
		}
	}

	/**
	 * ============================================================
	 * PATH NORMALIZATION
	 * ============================================================
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

	/**
	 * ============================================================
	 * DIRECTORY CREATION
	 * ============================================================
	 */
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
