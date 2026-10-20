#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include "native_probe.h"

using namespace godot;

namespace {

void initialize_wane_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(wane::NativeProbe);
}

void uninitialize_wane_module(ModuleInitializationLevel p_level) {
	(void)p_level;
}

} // namespace

extern "C" {

GDExtensionBool GDE_EXPORT wane_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_wane_module);
	init_obj.register_terminator(uninitialize_wane_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
