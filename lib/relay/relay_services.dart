import 'infra/beacon_signal.dart';
import 'infra/channel_store.dart';
import 'infra/masked_client.dart';
import 'infra/push_conduit.dart';
import 'infra/reach_check.dart';
import 'infra/relay_dispatch.dart';

/// Bundles the relay-layer singletons so `main` builds them once and the
/// coordinator/screens share them.
class RelayServices {
  RelayServices({
    required this.store,
    required this.reach,
    required this.client,
    required this.signal,
    required this.dispatch,
    required this.push,
  });

  final ChannelStore store;
  final ReachCheck reach;
  final MaskedClient client;
  final BeaconSignal signal;
  final RelayDispatch dispatch;
  final PushConduit push;

  /// User-Agent used by both the HTTP client and the WebView.
  String get userAgent => client.userAgent;

  static Future<RelayServices> boot() async {
    final store = await ChannelStore.open();
    final client = await MaskedClient.create();
    return RelayServices(
      store: store,
      reach: ReachCheck(),
      client: client,
      signal: BeaconSignal(client),
      dispatch: RelayDispatch(client),
      push: PushConduit(),
    );
  }
}
