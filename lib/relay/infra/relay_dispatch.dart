import 'dart:convert';

import '../../core/relay_log.dart';
import '../config/relay_config.dart';
import '../models/relay_reply.dart';
import 'masked_client.dart';

/// POSTs the assembled body to the config endpoint and parses the reply.
/// Any transport failure / non-200 / ok:false becomes a denied reply.
class RelayDispatch {
  RelayDispatch(this._client);

  final MaskedClient _client;

  Future<RelayReply> send(Map<String, dynamic> body) async {
    final encoded = jsonEncode(body);
    relayLog(() => '[SB] dispatch request body: $encoded');
    try {
      final resp = await _client.postJson(
        Uri.parse(RelayConfig.configEndpoint),
        body: encoded,
        timeout: RelayConfig.configTimeout,
      );
      relayLog(() => '[SB] dispatch response ${resp.statusCode}: ${resp.body}');
      // A received HTTP response — even a non-200 — means the server was
      // reached (rejected), which is distinct from a transport failure.
      if (resp.statusCode != 200) return const RelayReply.rejected();
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        return RelayReply.fromJson(decoded);
      }
      return const RelayReply.rejected();
    } catch (e) {
      relayLog(() => '[SB] dispatch failed: $e');
      return const RelayReply.denied();
    }
  }
}
