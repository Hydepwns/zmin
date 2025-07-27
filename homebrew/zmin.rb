class Zmin < Formula
  desc "Ultra-high-performance JSON minifier with 3.5+ GB/s throughput"
  homepage "https://github.com/hydepwns/zmin"
  url "https://github.com/hydepwns/zmin/archive/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"
  head "https://github.com/hydepwns/zmin.git", branch: "main"

  depends_on "zig" => :build

  def install
    # Build the project using Zig
    system "zig", "build", "-Doptimize=ReleaseFast"
    
    # Install binaries
    bin.install "zig-out/bin/zmin"
    bin.install "zig-out/bin/zmin-cli"
    
    # Install additional tools if they exist
    bin.install "zig-out/bin/zmin-format" if File.exist?("zig-out/bin/zmin-format")
    bin.install "zig-out/bin/zmin-validate" if File.exist?("zig-out/bin/zmin-validate")
    
    # Install documentation
    doc.install "README.md"
    doc.install "QUICK_REFERENCE.md" if File.exist?("QUICK_REFERENCE.md")
    doc.install "docs" if Dir.exist?("docs")
    
    # Install examples
    (share/"zmin/examples").install Dir["examples/*"] if Dir.exist?("examples")
    
    # Install man page if it exists
    man1.install "docs/zmin.1" if File.exist?("docs/zmin.1")
  end

  test do
    # Create a test JSON file
    test_json = '{"test": "data", "array": [1, 2, 3], "nested": {"key": "value"}}'
    expected = '{"test":"data","array":[1,2,3],"nested":{"key":"value"}}'
    
    # Test basic minification
    result = pipe_output("#{bin}/zmin", test_json).strip
    assert_equal expected, result
    
    # Test validation
    system "#{bin}/zmin", "--validate", "-", input: test_json
    assert_equal 0, $CHILD_STATUS.exitstatus
    
    # Test pretty printing
    pretty_result = pipe_output("#{bin}/zmin --pretty", test_json)
    assert pretty_result.include?("  ")
    
    # Test different modes
    %w[eco sport turbo].each do |mode|
      result = pipe_output("#{bin}/zmin --mode #{mode}", test_json).strip
      assert_equal expected, result
    end
    
    # Test CLI tool if it exists
    if File.exist?("#{bin}/zmin-cli")
      system "#{bin}/zmin-cli", "--help"
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
    
    # Test validation tool if it exists
    if File.exist?("#{bin}/zmin-validate")
      system "#{bin}/zmin-validate", "-", input: test_json
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end