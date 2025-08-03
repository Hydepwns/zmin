class Zmin < Formula
  desc "High-performance JSON minifier written in Zig"
  homepage "https://github.com/hydepwns/zmin"
  url "https://github.com/hydepwns/zmin/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/hydepwns/zmin.git", branch: "main"

  depends_on "zig" => :build

  def install
    system "zig", "build", "--release=fast"
    bin.install "zig-out/bin/zmin"

    # Install development tools
    bin.install "zig-out/bin/dev-server" if File.exist?("zig-out/bin/dev-server")
    bin.install "zig-out/bin/profiler" if File.exist?("zig-out/bin/profiler")
    bin.install "zig-out/bin/debugger" if File.exist?("zig-out/bin/debugger")
    bin.install "zig-out/bin/plugin-registry" if File.exist?("zig-out/bin/plugin-registry")
    bin.install "zig-out/bin/config-manager" if File.exist?("zig-out/bin/config-manager")
  end

  test do
    # Create a test JSON file
    (testpath/"test.json").write <<~EOS
      {
        "name": "test",
        "value": 42,
        "nested": {
          "array": [1, 2, 3]
        }
      }
    EOS

    # Test minification
    system "#{bin}/zmin", "test.json", "output.json"
    assert_predicate testpath/"output.json", :exist?

    # Verify output is minified
    output = File.read(testpath/"output.json")
    assert_equal '{"name":"test","value":42,"nested":{"array":[1,2,3]}}', output.strip
  end
end