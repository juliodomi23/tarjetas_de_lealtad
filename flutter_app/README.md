# App nativa (Flutter) — Tarjeta de lealtad

UI nativa iOS/Android que consume el **mismo backend Node** (`../server.js`).
No reescribe la lógica: solo reemplaza las pantallas web por nativas.

Pantallas: registro → tarjeta con QR y sellos (cliente) + escáner con cámara
(personal, protegido por clave). El escáner nativo es lo que justifica subirla
a las tiendas (Apple suele rechazar apps que solo "envuelven" una web).

## Generar el proyecto

Este repo solo trae `lib/` y `pubspec.yaml`. Las carpetas de plataforma
(`ios/`, `android/`) las crea Flutter:

```bash
cd flutter_app
flutter create .        # genera ios/ android/ sin tocar lib/ ni pubspec
flutter pub get
```

Antes de correr, edita la URL del negocio en `lib/api.dart`:

```dart
const apiBase = 'https://lealtad.tudominio.com';   // instancia de este negocio
```

> Una app build por negocio (cambia `apiBase`, nombre y colores), igual que
> "una instancia por cliente" en el backend.

## Permiso de cámara (obligatorio para el escáner)

- **iOS** — en `ios/Runner/Info.plist`:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Para escanear el código de la tarjeta de lealtad.</string>
  ```
- **Android** — `mobile_scanner` ya inyecta el permiso `CAMERA`. Asegura
  `minSdkVersion 21` en `android/app/build.gradle`.

## Correr y publicar

```bash
flutter run                 # probar en emulador/dispositivo
flutter build apk           # Android (prueba)
flutter build appbundle     # Android → Google Play
flutter build ipa           # iOS → App Store (requiere Mac + cuenta Apple)
```

Cuentas necesarias: **Google Play $25** (una vez), **Apple Developer $99/año**.
iOS solo se compila/sube desde una Mac (o un CI tipo Codemagic).

## Notas

- El backend no cambia: `/api/join`, `/api/card`, `/api/stamp`, `/api/config`.
  La validación y el anti-fraude (clave del personal) viven en el servidor.
- La PWA (`../public`) sigue siendo el camino rápido sin tiendas; esta app es
  para cuando un cliente exige presencia en App Store / Play Store.
