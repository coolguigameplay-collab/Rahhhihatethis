/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package states;

#if COPYSTATE_ALLOWED

import states.TitleState;
import lime.utils.Assets as LimeAssets;
import openfl.utils.Assets as OpenFLAssets;
import openfl.utils.ByteArray;
import haxe.io.Path;
import flixel.ui.FlxBar;
import flixel.ui.FlxBar.FlxBarFillDirection;
import lime.system.ThreadPool;

/**
 * ...
 * @author: Karim Akra
 */
class CopyState extends MusicBeatState
{
	private static final textFilesExtensions:Array<String> =
		['ini', 'txt', 'xml', 'hxs', 'hx', 'lua', 'json', 'frag', 'vert'];

	public static final IGNORE_FOLDER_FILE_NAME:String =
		"CopyState-Ignore.txt";

	private static var directoriesToIgnore:Array<String> = [];

	public static var locatedFiles:Array<String> = [];

	public static var maxLoopTimes:Int = 0;

	public var loadingImage:FlxSprite;
	public var loadingBar:FlxBar;
	public var loadedText:FlxText;
	public var thread:ThreadPool;

	var failedFilesStack:Array<String> = [];
	var failedFiles:Array<String> = [];

	var shouldCopy:Bool = false;
	var canUpdate:Bool = true;
	var loopTimes:Int = 0;

	override function create()
	{
		locatedFiles = [];
		maxLoopTimes = 0;

		checkExistingFiles();

		if (maxLoopTimes <= 0)
		{
			MusicBeatState.switchState(new TitleState());
			return;
		}

		CoolUtil.showPopUp(
			"Seems like you have some missing files that are necessary to run the game\nPress OK to begin the copy process",
			Language.getPhrase('mobile_notice', 'Notice!')
		);

		shouldCopy = true;

		add(
			new FlxSprite(0, 0).makeGraphic(
				FlxG.width,
				FlxG.height,
				0xffcaff4d
			)
		);

		loadingImage = new FlxSprite(
			0,
			0,
			Paths.image('funkay')
		);

		loadingImage.setGraphicSize(0, FlxG.height);
		loadingImage.updateHitbox();
		loadingImage.screenCenter();

		add(loadingImage);

		loadingBar = new FlxBar(
			0,
			FlxG.height - 26,
			FlxBarFillDirection.LEFT_TO_RIGHT,
			FlxG.width,
			26
		);

		loadingBar.setRange(0, maxLoopTimes);
		add(loadingBar);

		loadedText = new FlxText(
			loadingBar.x,
			loadingBar.y + 4,
			FlxG.width,
			'',
			16
		);

		loadedText.setFormat(
			Paths.font("vcr.ttf"),
			16,
			FlxColor.WHITE,
			CENTER
		);

		add(loadedText);

		thread = new ThreadPool(
			0,
			CoolUtil.getCPUThreadsCount()
		);

		thread.doWork.add(function(poop)
		{
			for (file in locatedFiles)
			{
				loopTimes++;

				/*
				 * Keep the original asset path here.
				 *
				 * Example:
				 * BFEXEOPT/mods/FunkinAvi/pack.json
				 *
				 * copyAsset() will convert the destination to:
				 * mods/FunkinAvi/pack.json
				 *
				 * This is important because OpenFLAssets must still
				 * read the original BFEXEOPT/... asset.
				 */
				copyAsset(file);
			}
		});

		new FlxTimer().start(0.5, (tmr) ->
		{
			thread.queue({});
		});

		super.create();
	}

	override function update(elapsed:Float)
	{
		if (shouldCopy)
		{
			if (loopTimes >= maxLoopTimes && canUpdate)
			{
				if (failedFiles.length > 0)
				{
					CoolUtil.showPopUp(
						failedFiles.join('\n'),
						'Failed To Copy ${failedFiles.length} File.'
					);

					if (!FileSystem.exists('logs'))
						FileSystem.createDirectory('logs');

					File.saveContent(
						'logs/' +
						Date.now().toString()
							.replace(' ', '-')
							.replace(':', "'") +
						'-CopyState.txt',
						failedFilesStack.join('\n')
					);
				}

				FlxG.sound.play(Paths.sound('confirmMenu')).onComplete = () ->
				{
					MusicBeatState.switchState(new TitleState());
				};

				canUpdate = false;
			}

			if (loopTimes >= maxLoopTimes)
				loadedText.text = "Completed!";
			else
				loadedText.text = '$loopTimes/$maxLoopTimes';

			loadingBar.percent =
				Math.min(
					(loopTimes / maxLoopTimes) * 100,
					100
				);
		}

		super.update(elapsed);
	}

	/**
	 * Copies a bundled asset to the external game directory.
	 *
	 * Source example:
	 * BFEXEOPT/mods/FunkinAvi/pack.json
	 *
	 * Destination example:
	 * mods/FunkinAvi/pack.json
	 */
	public function copyAsset(file:String)
	{
		var outputFile:String = getOutputPath(file);

		/*
		 * If the destination already exists, do not copy it again.
		 */
		if (FileSystem.exists(outputFile))
			return;

		var directory:String = Path.directory(outputFile);

		if (!FileSystem.exists(directory))
			ensureDirectory(directory);

		try
		{
			/*
			 * IMPORTANT:
			 *
			 * getFile(file) receives the ORIGINAL source path.
			 *
			 * Therefore:
			 * BFEXEOPT/mods/FunkinAvi/file.png
			 *
			 * is still looked up as:
			 * BFEXEOPT/mods/FunkinAvi/file.png
			 */
			var sourceFile:String = getFile(file);

			if (OpenFLAssets.exists(sourceFile))
			{
				if (textFilesExtensions.contains(
					Path.extension(outputFile).toLowerCase()
				))
				{
					createContentFromInternal(
						file,
						outputFile
					);
				}
				else
				{
					var bytes:ByteArray =
						getFileBytes(sourceFile);

					File.saveBytes(
						outputFile,
						bytes
					);
				}
			}
			else
			{
				failedFiles.push(
					sourceFile +
					" (File Dosen't Exist)"
				);

				failedFilesStack.push(
					'Asset ' +
					sourceFile +
					' does not exist.'
				);
			}
		}
		catch (e:haxe.Exception)
		{
			failedFiles.push(
				'${getFile(file)} (${e.message})'
			);

			failedFilesStack.push(
				'${getFile(file)} (${e.stack})'
			);
		}
	}

	/**
	 * Converts the bundled BFEXEOPT path into the
	 * actual external storage destination.
	 *
	 * BFEXEOPT/mods/FunkinAvi/file
	 * ->
	 * mods/FunkinAvi/file
	 *
	 * Normal assets such as:
	 * assets/images/file.png
	 *
	 * remain unchanged.
	 */
	private static function getOutputPath(file:String):String
	{
		if (file.startsWith('BFEXEOPT/'))
		{
			return file.substr('BFEXEOPT/'.length);
		}

		return file;
	}

	/**
	 * Writes text-based bundled files.
	 *
	 * sourceFile:
	 * BFEXEOPT/mods/FunkinAvi/pack.json
	 *
	 * outputFile:
	 * mods/FunkinAvi/pack.json
	 */
	public function createContentFromInternal(
		sourceFile:String,
		outputFile:String
	)
	{
		try
		{
			var fileData:String =
				OpenFLAssets.getText(
					getFile(sourceFile)
				);

			if (fileData == null)
				fileData = '';

			var directory:String =
				Path.directory(outputFile);

			if (!FileSystem.exists(directory))
				ensureDirectory(directory);

			File.saveContent(
				outputFile,
				fileData
			);
		}
		catch (e:haxe.Exception)
		{
			failedFiles.push(
				'${getFile(sourceFile)} (${e.message})'
			);

			failedFilesStack.push(
				'${getFile(sourceFile)} (${e.stack})'
			);
		}
	}

	public function getFileBytes(file:String):ByteArray
	{
		switch (Path.extension(file).toLowerCase())
		{
			case 'otf' | 'ttf':
				return ByteArray.fromFile(file);

			default:
				return OpenFLAssets.getBytes(file);
		}
	}

	public static function getFile(file:String):String
	{
		if (OpenFLAssets.exists(file))
			return file;

		@:privateAccess
		for (library in LimeAssets.libraries.keys())
		{
			if (
				OpenFLAssets.exists(
					'$library:$file'
				)
				&& library != 'default'
			)
			{
				return '$library:$file';
			}
		}

		return file;
	}

	/**
	 * Finds bundled assets that still need to be copied.
	 *
	 * Normal game assets:
	 * assets/...
	 *
	 * Bundled BFEXEOPT mods:
	 * BFEXEOPT/mods/...
	 */
	public static function checkExistingFiles():Bool
	{
		locatedFiles = OpenFLAssets.list();

		/*
		 * Normal assets used by CopyState.
		 */
		var assets = locatedFiles.filter(
			folder -> folder.startsWith('assets/')
		);

		/*
		 * BFEXEOPT bundled mods.
		 *
		 * These are intentionally kept with the
		 * BFEXEOPT/ prefix here so OpenFLAssets can
		 * correctly read the source file.
		 */
		var mods = locatedFiles.filter(
			folder -> folder.startsWith('BFEXEOPT/mods/')
		);

		locatedFiles = assets.concat(mods);

		/*
		 * Check the DESTINATION path, not the source
		 * BFEXEOPT path.
		 */
		locatedFiles = locatedFiles.filter(
			file -> !FileSystem.exists(
				getOutputPath(file)
			)
		);

		var filesToRemove:Array<String> = [];

		for (file in locatedFiles)
		{
			if (filesToRemove.contains(file))
				continue;

			if (
				file.endsWith(
					IGNORE_FOLDER_FILE_NAME
				)
				&&
				!directoriesToIgnore.contains(
					Path.directory(file)
				)
			)
			{
				directoriesToIgnore.push(
					Path.directory(file)
				);
			}

			if (directoriesToIgnore.length > 0)
			{
				for (directory in directoriesToIgnore)
				{
					if (file.startsWith(directory))
						filesToRemove.push(file);
				}
			}
		}

		locatedFiles =
			locatedFiles.filter(
				file -> !filesToRemove.contains(file)
			);

		maxLoopTimes = locatedFiles.length;

		return (maxLoopTimes <= 0);
	}

	/**
	 * Creates a directory and all missing parent
	 * directories.
	 */
	private static function ensureDirectory(
		directory:String
	):Void
	{
		if (directory == null || directory.length == 0)
			return;

		if (FileSystem.exists(directory))
			return;

		var parent:String =
			Path.directory(directory);

		if (
			parent != directory
			&&
			parent.length > 0
			&&
			!FileSystem.exists(parent)
		)
		{
			ensureDirectory(parent);
		}

		if (!FileSystem.exists(directory))
			FileSystem.createDirectory(directory);
	}
}

#end
