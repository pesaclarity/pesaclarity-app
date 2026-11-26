// Signs Ask's model catalogue.
//
//   ASK_MODELS_SIGNING_SEED=<base64 of 32 bytes> \
//     dart run tool/sign_ask_models.dart tool/ask_models.json
//
// Reads the models from the JSON list given (the fields of AskModelEntry),
// and writes assets/models/ask/ask-models.signed.json. With --public it
// prints only the public key, for askModelCataloguePublicKeys. The seed is
// a secret: keep it out of the repository and out of logs.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_catalogue.dart';

Future<void> main(List<String> args) async {
  final seed = Platform.environment['ASK_MODELS_SIGNING_SEED'];
  if (seed == null || seed.isEmpty) {
    stderr.writeln('Set ASK_MODELS_SIGNING_SEED.');
    exit(2);
  }
  final keys = await Ed25519().newKeyPairFromSeed(base64.decode(seed));
  final public = base64.encode((await keys.extractPublicKey()).bytes);
  if (args.contains('--public')) {
    stdout.writeln(public);
    return;
  }
  if (args.isEmpty) {
    stderr.writeln('Give the models JSON file.');
    exit(2);
  }
  final entries = [
    for (final item in jsonDecode(File(args.first).readAsStringSync()) as List)
      AskModelEntry.tryParse(item) ??
          (throw FormatException('Bad model entry: $item')),
  ];
  final payload = utf8.encode(jsonEncode(AskModelCatalogue.payload(entries)));
  final signature = await Ed25519().sign(
    AskModelCatalogue.signedBytes(payload),
    keyPair: keys,
  );
  final envelope = {
    'alg': 'Ed25519',
    'payload': base64.encode(payload),
    'signature': base64.encode(signature.bytes),
  };
  File(askModelCatalogueAsset).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(envelope)}\n',
  );
  final check = await AskModelCatalogue.verify(envelope);
  if (check.models.length != entries.length) {
    stderr.writeln(
      'Signed, but the app would not accept it: is $public in '
      'askModelCataloguePublicKeys?',
    );
    exit(1);
  }
  stdout.writeln('Wrote $askModelCatalogueAsset (${entries.length} models).');
}
