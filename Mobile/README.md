# AutoMAA Mobile

iOS and Android companion for the native macOS AutoMAA application. The Mac runs every workflow; the phone displays existing plans, progress and redacted history, and requests resume or safe stop.

See [connection and usage](../docs/guide/mobile.md) and [development and isolated testing](../docs/development/mobile.md).

## Development

Use Flutter 3.47.6 / Dart 3.13.5, Xcode for iOS, and the Android SDK for Android. Run `flutter pub get`, `flutter analyze` and `flutter test test/mobile_client_test.dart` before building. Use `flutter build ios --simulator --debug` or `flutter build apk --debug` for local acceptance builds. Physical iOS devices require signing with your own development team.

Production pairing accepts only HTTPS-backed Tailscale WebSocket endpoints. Test-only transports and fixtures are injected from `test/` and `integration_test/`; there is no production bypass for TLS, authorization or workflow validation.

This client has no App Store or Play Store release. Keep the Mac awake and AutoMAA running. Real-device camera, Tailscale/VPN and background recovery require physical-device acceptance tests.

Project branding remains subject to [Assets/README.md](../Assets/README.md), not the source-code MIT license.
