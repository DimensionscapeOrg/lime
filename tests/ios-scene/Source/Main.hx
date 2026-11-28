package;

import haxe.io.Path;
import lime.app.Application;
import lime.graphics.RenderContext;
import lime.system.System;

/**
	Logs what an iOS application hears as it launches, goes to the background and
	back, and is opened with a URL, to a file in its documents folder that the
	runner reads from the simulator.
**/
class Main extends Application
{
	private static var logPath:String;

	private var frames = 0;

	public function new()
	{
		super();
		log("STARTED");
	}

	public override function onWindowCreate():Void
	{
		log("WINDOW " + window.width + "x" + window.height);
		window.onActivate.add(function() log("ACTIVATE " + window.width + "x" + window.height));
		window.onDeactivate.add(function() log("DEACTIVATE"));
		window.onResize.add(function(width, height) log("RESIZE " + width + "x" + height));
		window.onDropFile.add(function(path) log("DROP " + path));
	}

	public override function render(context:RenderContext):Void
	{
		frames++;
		if (frames == 1 || frames == 60) log("FRAME " + frames + " " + window.width + "x" + window.height);

		switch (context.type)
		{
			case OPENGL, OPENGLES, WEBGL:
				var gl = context.webgl;
				gl.clearColor(1, 0, 1, 1);
				gl.clear(gl.COLOR_BUFFER_BIT);

			default:
		}
	}

	private static function log(message:String):Void
	{
		Sys.println("SCENECHECK " + message);

		try
		{
			if (logPath == null) logPath = Path.join([System.documentsDirectory, "scenecheck.log"]);
			var output = sys.io.File.append(logPath, false);
			output.writeString(Date.now().toString() + " " + message + "\n");
			output.close();
		}
		catch (e:Dynamic)
		{
			Sys.println("SCENECHECK could not write the log: " + e);
		}
	}
}
