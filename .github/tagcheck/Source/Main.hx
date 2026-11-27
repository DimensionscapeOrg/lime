package;

import haxe.io.Bytes;
import lime.app.Application;
import lime.graphics.RenderContext;
import lime.graphics.WebGLRenderContext;
import lime.graphics.cairo.Cairo;
import lime.graphics.cairo.CairoFormat;
import lime.graphics.cairo.CairoImageSurface;
import lime.utils.DataPointer;
import lime.utils.Float32Array;
import lime.utils.UInt8Array;

/**
	Fills the screen with three bands, top to bottom:

	- whether the heap tags its addresses: white if it does, blue if it doesn't (then the
	  bands below tell nothing)
	- Cairo painting through a DataPointer into a buffer: green if the bytes changed, red if not
	- OpenGL drawing a quad from a buffer uploaded through a DataPointer and reading it back:
	  green if every pixel read is the quad's, red if not

	It also traces one line, "TagCheck: ...", for adb logcat.
**/
class Main extends Application
{
	private static inline var PASSED = 1;
	private static inline var FAILED = 2;
	private static inline var UNTAGGED = 3;

	private var checked = false;
	private var topByte = 0;
	private var cairoResult = 0;
	private var glResult = 0;

	public function new()
	{
		super();
	}

	public override function render(context:RenderContext):Void
	{
		var gl:WebGLRenderContext = switch (context.type)
		{
			case OPENGL, OPENGLES, WEBGL: context.webgl;
			default: null;
		}

		if (gl == null) return;

		var width = Std.int(window.width * window.scale);
		var height = Std.int(window.height * window.scale);

		if (!checked)
		{
			checked = true;
			topByte = topByteOfHeap();
			cairoResult = checkCairo();
			glResult = checkOpenGL(gl, width, height);
			trace("TagCheck: heap top byte 0x" + StringTools.hex(topByte, 2) + ", Cairo " + word(cairoResult) + ", OpenGL " + word(glResult));
		}

		gl.viewport(0, 0, width, height);
		gl.enable(gl.SCISSOR_TEST);

		var third = Std.int(height / 3);
		band(gl, 0, third, width, glResult);
		band(gl, third, third, width, cairoResult);
		band(gl, third * 2, height - third * 2, width, topByte != 0 ? 0 : UNTAGGED);

		gl.disable(gl.SCISSOR_TEST);
	}

	private static function band(gl:WebGLRenderContext, y:Int, bandHeight:Int, width:Int, result:Int):Void
	{
		gl.scissor(0, y, width, bandHeight);

		switch (result)
		{
			case PASSED:
				gl.clearColor(0, 0.8, 0, 1);
			case FAILED:
				gl.clearColor(0.9, 0, 0, 1);
			case UNTAGGED:
				gl.clearColor(0, 0, 0.9, 1);
			default:
				gl.clearColor(1, 1, 1, 1);
		}

		gl.clear(gl.COLOR_BUFFER_BIT);
	}

	private static function word(result:Int):String
	{
		return result == PASSED ? "passed" : (result == FAILED ? "failed" : "not run");
	}

	// The top byte of an address the heap gives out
	private static function topByteOfHeap():Int
	{
		var bytes = Bytes.alloc(65536);
		var data = cpp.Pointer.arrayElem(bytes.getData(), 0).ptr;
		return untyped __cpp__('(int)((unsigned long long)(uintptr_t){0} >> 56)', data);
	}

	// Cairo paints 16 bytes in the middle of a buffer, so that an address moved by up to
	// 1 KB still lands inside it
	private static function checkCairo():Int
	{
		var bytes = Bytes.alloc(65536);
		bytes.fill(0, bytes.length, 0);

		var view = UInt8Array.fromBytes(bytes, 32768, 16);
		var surface = CairoImageSurface.create(DataPointer.fromArrayBufferView(view), CairoFormat.ARGB32, 4, 1, 16);
		var cairo = new Cairo(surface);
		cairo.setSourceRGBA(1, 1, 1, 1);
		cairo.paint();
		surface.flush();

		for (i in 0...16)
		{
			if (bytes.get(32768 + i) != 0xFF) return FAILED;
		}

		return PASSED;
	}

	// A quad over the whole viewport, drawn from vertices and read back into pixels the heap holds
	private static function checkOpenGL(gl:WebGLRenderContext, width:Int, height:Int):Int
	{
		var vertexShader = gl.createShader(gl.VERTEX_SHADER);
		gl.shaderSource(vertexShader, "attribute vec2 position; void main() { gl_Position = vec4(position, 0.0, 1.0); }");
		gl.compileShader(vertexShader);

		var fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
		gl.shaderSource(fragmentShader, "#ifdef GL_ES\nprecision mediump float;\n#endif\nvoid main() { gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0); }");
		gl.compileShader(fragmentShader);

		var program = gl.createProgram();
		gl.attachShader(program, vertexShader);
		gl.attachShader(program, fragmentShader);
		gl.linkProgram(program);
		gl.useProgram(program);

		var position = gl.getAttribLocation(program, "position");
		var vertices = new Float32Array([-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0]);
		var buffer = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
		gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
		gl.enableVertexAttribArray(position);
		gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

		gl.viewport(0, 0, width, height);
		gl.clearColor(0, 0, 0, 1);
		gl.clear(gl.COLOR_BUFFER_BIT);
		gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

		var points = [[width >> 1, height >> 1], [4, 4], [width - 5, 4], [4, height - 5], [width - 5, height - 5]];
		var pixel = new UInt8Array(4);
		var result = PASSED;

		for (point in points)
		{
			for (i in 0...4)
			{
				pixel[i] = 0x7F;
			}

			gl.readPixels(point[0], point[1], 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);

			if (pixel[0] != 0 || pixel[1] != 0xFF || pixel[2] != 0)
			{
				result = FAILED;
			}
		}

		gl.disableVertexAttribArray(position);
		gl.bindBuffer(gl.ARRAY_BUFFER, null);
		gl.useProgram(null);
		return result;
	}
}
