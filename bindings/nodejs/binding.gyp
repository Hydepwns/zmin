{
  "targets": [
    {
      "target_name": "zmin",
      "sources": [
        "src/binding.cpp"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "../../src/bindings"
      ],
      "dependencies": [
        "<!(node -p \"require('node-addon-api').gyp\")"
      ],
      "cflags!": [ "-fno-exceptions" ],
      "cflags_cc!": [ "-fno-exceptions" ],
      "defines": [ "NAPI_DISABLE_CPP_EXCEPTIONS" ],
      "libraries": [
        "-L../../zig-out/lib",
        "-lzmin"
      ],
      "conditions": [
        ["OS=='linux'", {
          "libraries": [
            "-L../../zig-out/lib",
            "-lzmin"
          ]
        }],
        ["OS=='mac'", {
          "libraries": [
            "-L../../zig-out/lib",
            "-lzmin"
          ]
        }],
        ["OS=='win'", {
          "libraries": [
            "-L../../zig-out/lib",
            "-lzmin.lib"
          ]
        }]
      ]
    }
  ]
} 