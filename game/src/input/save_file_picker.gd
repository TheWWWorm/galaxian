extends RefCounted
signal selected(path: String)
signal failed(message: String)
var callback: JavaScriptObject
var pending := false
const PATH := "/tmp/gof-transfer.gofsave"


func choose() -> void:
	if pending:
		return
	pending = true
	if callback == null:
		callback = JavaScriptBridge.create_callback(receive)
	(
		JavaScriptBridge
		. eval(
			"""
window.gofChooseSave = function(done) {
 const input = document.createElement('input');
 input.type = 'file'; input.accept = '.gofsave,.json'; input.hidden = true;
 document.body.appendChild(input);
 input.addEventListener('cancel', () => { input.remove(); done('cancel'); }, {once:true});
 input.addEventListener('change', async () => {
  const file = input.files[0]; input.remove();
  if (!file) { done('cancel'); return; }
  if (file.size > 16*1024*1024) { done('error','Choose a save export under 16 MiB.'); return; }
  try { done('file', new Uint8Array(await file.arrayBuffer())); }
  catch (_) { done('error','The selected save could not be read.'); }
 }, {once:true});
 input.click();
};
""",
			true
		)
	)
	JavaScriptBridge.get_interface("window").gofChooseSave(callback)


func receive(args: Array) -> void:
	pending = false
	if args[0] == "cancel":
		return
	if args[0] == "error":
		failed.emit(str(args[1]))
		return
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		failed.emit("Could not stage the save import.")
		return
	file.store_buffer(JavaScriptBridge.js_buffer_to_packed_byte_array(args[1]))
	file.close()
	selected.emit(PATH)
	DirAccess.remove_absolute(PATH)
