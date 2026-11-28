package;

import lime.app.Application;
import lime.graphics.RenderContext;
import lime.system.System;

class Main extends Application
{
	private var frames = 0;

	public function new()
	{
		super();
	}

	public override function render(context:RenderContext):Void
	{
		frames++;

		if (frames == 30)
		{
			Sys.println("SCENEHELPER OPEN scenecheck://cold");
			System.openURL("scenecheck://cold");
		}
	}
}
