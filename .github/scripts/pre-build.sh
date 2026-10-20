#!/bin/bash
# Zeus-specific steps for the shared TestFlight workflow (.github/workflows/ios-testflight.yml).
# Runs after Xcode is selected and before XcodeGen generates the project.
set -euo pipefail

# Secrets.plist (Open Charge Map key) must exist before `xcodegen generate` so it's bundled.
key=$(jq -r '.OPENCHARGEMAP_KEY // empty' <<<"$SECRETS_JSON")
cat > Sources/Zeus/Resources/Secrets.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>OpenChargeMapKey</key>
<string>$key</string>
</dict></plist>
PLIST
echo "Secrets.plist written (key present: $([ -n "$key" ] && echo yes || echo NO))"

# appintentsnltrainingprocessor fails with "Unable to parse Info.plist" on Xcode 26.x. It only
# builds Spotlight SSU search-suggestion assets; App Intents metadata (what Siri needs) comes from
# a different tool. Stub it to a no-op so the archive completes.
ssu="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsnltrainingprocessor"
if [ -f "$ssu" ]; then
  sudo mv "$ssu" "$ssu.real"
  printf '#!/bin/bash\nexit 0\n' | sudo tee "$ssu" > /dev/null
  sudo chmod +x "$ssu"
  echo "Stubbed appintentsnltrainingprocessor (SSU training) to a no-op."
fi
