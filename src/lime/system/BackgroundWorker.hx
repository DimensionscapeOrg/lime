package lime.system;

import lime.app.Application;
import lime.app.Event;
#if sys
#if haxe4
import sys.thread.Deque;
import sys.thread.Thread;
#elseif cpp
import cpp.vm.Deque;
import cpp.vm.Thread;
#elseif neko
import neko.vm.Deque;
import neko.vm.Thread;
#end
#end
/**
	A `BackgroundWorker` allows the execution of a function on a background thread, 
	avoiding the blocking of the main thread. This is particularly useful for long-running 
	operations like file I/O, network requests, or computationally intensive tasks.

	### Notes:
	- **Thread Support:** Only system targets (such as C++, Neko) support threading. 
	- **Events:** The class uses the `Event` class to dispatch completion, error, 
	  and progress notifications.

	@see `ThreadPool` for more advanced threading capabilities, including thread 
	safety, HTML5 threads, and more robust handling of tasks.
**/
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class BackgroundWorker
{
	private static var MESSAGE_COMPLETE = "__COMPLETE__";
	private static var MESSAGE_ERROR = "__ERROR__";

	/**
		Indicates whether the worker has been canceled.
	**/
	public var canceled(default, null):Bool;

	/**
		Indicates whether the worker has completed its task.
	**/
	public var completed(default, null):Bool;

	/**
		Dispatched when the worker is about to perform its task.
		The function to execute should be added as a listener to this event.
	**/
	public var doWork = new Event<Dynamic->Void>();

	/**
		Dispatched when the worker has successfully completed its task.
	**/
	public var onComplete = new Event<Dynamic->Void>();

	/**
		Dispatched if an error occurs during the execution of the worker's task.
	**/
	public var onError = new Event<Dynamic->Void>();

	/**
		Dispatched periodically during the worker's task to provide progress updates.
	**/
	public var onProgress = new Event<Dynamic->Void>();

	@:noCompletion private var __runMessage:Dynamic;
	#if (cpp || neko || (haxe4 && hl))
	@:noCompletion private var __messageQueue:Deque<Dynamic>;
	@:noCompletion private var __workerThread:Thread;
	#end

	/**
		Creates a new `BackgroundWorker` instance.
	**/
	public function new() {}

	/**
		Cancels the worker's task if it is still running. This won't stop the thread 
		immediately.
	**/
	public function cancel():Void
	{
		canceled = true;

		#if (cpp || neko || (haxe4 && hl))
		__workerThread = null;

		// Nothing more is dispatched, so the worker's messages needn't be read
		if (Application.current != null)
		{
			Application.current.onUpdate.remove(__update);
		}
		#end
	}

	/**
		Starts the worker's task, optionally passing a message to the task.
		@param message An optional message to pass to the worker's task.
	**/
	public function run(message:Dynamic = null):Void
	{
		canceled = false;
		completed = false;
		__runMessage = message;

		#if (cpp || neko || (haxe4 && hl))
		__messageQueue = new Deque<Dynamic>();
		__workerThread = Thread.create(__doWork);

		// TODO: Better way to do this

		if (Application.current != null)
		{
			Application.current.onUpdate.add(__update);
		}
		#else
		__doWork();
		#end
	}

	/**
		Sends a completion message, indicating that the worker has finished its task.
		@param message An optional message to pass to the `onComplete` event.
	**/
	public function sendComplete(message:Dynamic = null):Void
	{
		completed = true;

		#if (cpp || neko || (haxe4 && hl))
		__messageQueue.add(MESSAGE_COMPLETE);
		__messageQueue.add(message);
		#else
		if (!canceled)
		{
			canceled = true;
			onComplete.dispatch(message);
		}
		#end
	}

	/**
		Sends an error message, indicating that an error occurred during the worker's task.
		@param message An optional message to pass to the `onError` event.
	**/
	public function sendError(message:Dynamic = null):Void
	{
		#if (cpp || neko || (haxe4 && hl))
		__messageQueue.add(MESSAGE_ERROR);
		__messageQueue.add(message);
		#else
		if (!canceled)
		{
			canceled = true;
			onError.dispatch(message);
		}
		#end
	}

	/**
		Sends a progress update message.
		@param message An optional message to pass to the `onProgress` event.
	**/
	public function sendProgress(message:Dynamic = null):Void
	{
		#if (cpp || neko || (haxe4 && hl))
		__messageQueue.add(message);
		#else
		if (!canceled)
		{
			onProgress.dispatch(message);
		}
		#end
	}

	@:noCompletion private function __doWork():Void
	{
		doWork.dispatch(__runMessage);

		// #if (cpp || neko)
		//
		// __messageQueue.add (MESSAGE_COMPLETE);
		//
		// #else
		//
		// if (!canceled) {
		//
		// canceled = true;
		// onComplete.dispatch (null);
		//
		// }
		//
		// #end
	}

	@:noCompletion private function __update(deltaTime:Int):Void
	{
		#if (cpp || neko || (haxe4 && hl))
		// Every message that has arrived is dispatched, as ThreadPool does, rather
		// than one a frame
		var queue = __messageQueue;
		var message:Dynamic;

		while ((message = queue.pop(false)) != null)
		{
			if (message == MESSAGE_ERROR || message == MESSAGE_COMPLETE)
			{
				Application.current.onUpdate.remove(__update);

				// The worker adds the payload straight after, so it's waited for
				var payload = queue.pop(true);

				if (!canceled)
				{
					canceled = true;

					if (message == MESSAGE_ERROR)
					{
						onError.dispatch(payload);
					}
					else
					{
						onComplete.dispatch(payload);
					}
				}

				break;
			}
			else if (!canceled)
			{
				onProgress.dispatch(message);
			}
		}
		#end
	}
}
