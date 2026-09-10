extends RefCounted
## Browser-selected archives live only in the temporary virtual filesystem.
signal selected(path: String)
signal failed(message: String)
var callback: JavaScriptObject
var pending := false
const PATH := "/tmp/gof-selected.ipa"

func choose() -> void:
	if pending:
		return
	pending = true
	if callback == null:
		callback = JavaScriptBridge.create_callback(receive)
	JavaScriptBridge.eval("""
window.gofChooseArchive = function(done) {
 const input = document.createElement('input');
 input.type = 'file'; input.accept = '.ipa'; input.hidden = true;
 document.body.appendChild(input);
 input.addEventListener('cancel', () => { input.remove(); done('cancel'); }, {once:true});
 input.addEventListener('change', async () => {
  const file = input.files[0]; input.remove();
  if (!file) { done('cancel'); return; }
  if (file.size > 128 * 1024 * 1024) { done('error', 'Choose an IPA under 128 MiB.'); return; }
  try { done('file', new Uint8Array(await file.arrayBuffer())); }
  catch (_) { done('error', 'The selected file could not be read.'); }
 }, {once:true});
 input.click();
};
""", true)
	JavaScriptBridge.get_interface("window").gofChooseArchive(callback)

func receive(args: Array) -> void:
	pending = false
	if args[0] == "cancel":
		return
	if args[0] == "error":
		failed.emit(str(args[1]))
		return
	var bytes := JavaScriptBridge.js_buffer_to_packed_byte_array(args[1])
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		failed.emit("The browser could not stage this archive.")
		return
	file.store_buffer(bytes)
	file.close()
	selected.emit(PATH)

func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
