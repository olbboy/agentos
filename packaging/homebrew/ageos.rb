# Cask for the olbboy/homebrew-tap. sha256 is of the released AgeOS-vX.Y.Z.zip.
# Unsigned (no Developer ID): Homebrew removed --no-quarantine, so a blocked app
# is cleared with:
#   find /Applications/AgeOS.app -exec xattr -d com.apple.quarantine {} \; 2>/dev/null
cask "ageos" do
  version "0.1.0"
  sha256 "15ce470f6ba668a0a3dea55f481187cac0e8cce02c498ae3f7f4673e1d229952"

  url "https://github.com/olbboy/agentos/releases/download/v#{version}/AgeOS-v#{version}.zip"
  name "AgeOS"
  desc "One library for Agent Skills and MCP servers, distributed to every coding agent"
  homepage "https://github.com/olbboy/agentos"

  depends_on macos: ">= :tahoe"

  app "AgeOS.app"

  # CLI đi kèm bản tarball riêng; hoặc lấy từ app bundle khi gộp về sau.
  caveats <<~EOS
    Bản chưa ký Developer ID — nếu macOS chặn khi mở, gỡ quarantine (macOS 26 bỏ cờ -r):
      find "#{appdir}/AgeOS.app" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null
    CLI: tải ageos-cli-v#{version}-arm64.tar.gz từ trang Releases.
  EOS
end
