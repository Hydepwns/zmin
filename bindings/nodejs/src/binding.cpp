#include <napi.h>
#include <string>
#include <vector>

// Include the zmin C API
extern "C" {
#include "c_api.h"
}

class ZminBinding : public Napi::ObjectWrap<ZminBinding> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports) {
        Napi::Function func = DefineClass(env, "Zmin", {
            InstanceMethod("minify", &ZminBinding::Minify),
            InstanceMethod("validate", &ZminBinding::Validate),
            InstanceMethod("getVersion", &ZminBinding::GetVersion),
        });

        Napi::FunctionReference* constructor = new Napi::FunctionReference();
        *constructor = Napi::Persistent(func);
        env.SetInstanceData(constructor);

        exports.Set("Zmin", func);
        return exports;
    }

    ZminBinding(const Napi::CallbackInfo& info) : Napi::ObjectWrap<ZminBinding>(info) {
        // Initialize the zmin library
        zmin_init();
    }

private:
    Napi::Value Minify(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();

        if (info.Length() < 1) {
            Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
            return env.Null();
        }

        if (!info[0].IsString()) {
            Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
            return env.Null();
        }

        std::string input = info[0].As<Napi::String>();
        
        // Default to SPORT mode
        int mode = 1; // SPORT
        if (info.Length() > 1 && info[1].IsNumber()) {
            mode = info[1].As<Napi::Number>().Int32Value();
        }

        // Call zmin_minify_mode
        zmin_result_t result = zmin_minify_mode(input.c_str(), input.length(), mode);
        
        if (result.error_code != 0) {
            std::string error_msg = "Minification failed with error code: " + std::to_string(result.error_code);
            zmin_free_result(&result);
            Napi::Error::New(env, error_msg).ThrowAsJavaScriptException();
            return env.Null();
        }

        // Convert result to JavaScript string
        std::string output(result.data, result.size);
        zmin_free_result(&result);
        
        return Napi::String::New(env, output);
    }

    Napi::Value Validate(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();

        if (info.Length() < 1) {
            Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
            return env.Null();
        }

        if (!info[0].IsString()) {
            Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
            return env.Null();
        }

        std::string input = info[0].As<Napi::String>();
        
        // Call zmin_validate
        int result = zmin_validate(input.c_str(), input.length());
        
        return Napi::Boolean::New(env, result != 0);
    }

    Napi::Value GetVersion(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        const char* version = zmin_get_version();
        return Napi::String::New(env, version);
    }
};

// Module initialization
Napi::Object Init(Napi::Env env, Napi::Object exports) {
    return ZminBinding::Init(env, exports);
}

NODE_API_MODULE(zmin, Init) 