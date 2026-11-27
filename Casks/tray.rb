cask "tray" do
  version :latest
  sha256 :no_check

  url "https://github.com/lrjulia/tray/releases/latest/download/Tray.zip"
  name "Tray"
  desc "Clipboard history for macOS"
  homepage "https://github.com/lrjulia/tray"

  depends_on macos: ">= :sonoma"

  app "Tray.app"

  zap trash: [
    "~/Library/Application Support/Tray",
    "~/Library/Preferences/app.tray.Tray.plist",
  ]
end
