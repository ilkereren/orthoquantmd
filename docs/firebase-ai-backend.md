# Firebase AI Backend Setup

This project uses Firebase Functions as a small proxy for OrthoQuant AI.
The app never receives the OrthoQuant OpenAI key. The function owns:

- OpenAI API key
- fixed OpenAI model
- weekly OrthoQuant quota
- OpenAI request/response handling

## One-time local setup

Install the Firebase CLI and FlutterFire CLI:

```sh
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

Sign in and connect this repo to your Firebase project:

```sh
firebase login
firebase use --add
```

The current Firebase project is `orthoquantmd`.

Firebase Functions, Secret Manager, Cloud Build, Cloud Run, and Artifact
Registry require a Firebase Blaze plan / Google Cloud billing account.
Enable billing for the project before deploying the AI proxy.

If you later add Firebase SDK plugins to Flutter, run:

```sh
flutterfire configure
```

## Secret setup

Set the OpenAI key as a Firebase Function secret:

```sh
firebase functions:secrets:set OPENAI_API_KEY
```

Do not put this key in Flutter source, `firebase.json`, or `.env` files that are committed.

## Deploy

```sh
cd functions
npm install
cd ..
firebase deploy --only functions
```

After deploy, Firebase prints the `interpretResults` HTTPS URL.
Use that URL when running or building Flutter:

```sh
flutter run -d web-server \
  --web-hostname 127.0.0.1 \
  --web-port 5173 \
  --dart-define=ORTHOQUANT_AI_PROXY_URL=https://REGION-PROJECT.cloudfunctions.net/interpretResults
```

## Notes

The function enforces 10 OrthoQuant AI calls per installation id per UTC week.
For production, add Firebase App Check and stricter abuse monitoring before public launch.
