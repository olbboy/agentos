# Template cask cho tap <owner>/homebrew-tap — điền version/sha256/owner khi publish.
# Chưa ký Developer ID → hướng dẫn user: brew install --cask ageos --no-quarantine
cask "ageos" do
  version "0.1.0"
  sha256 "PLACEHOLDER_SHA256_CUA_AgeOS-#{version}.zip"

  url "https://github.com/OWNER/agentos/releases/download/v#{version}/AgeOS-v#{version}.zip"
  name "AgeOS"
  desc "One library for Agent Skills and MCP servers, distributed to every coding agent"
  homepage "https://github.com/OWNER/agentos"

  depends_on macos: ">= :tahoe"

  app "AgeOS.app"

  # CLI đi kèm bản tarball riêng; hoặc lấy từ app bundle khi gộp về sau.
  caveats <<~EOS
    Bản chưa ký Developer ID — nếu macOS chặn, chạy:
      xattr -dr com.apple.quarantine "#{appdir}/AgeOS.app"
    CLI: tải ageos-cli-v#{version}-arm64.tar.gz từ trang Releases.
  EOS
end
