import 'dart:async';
import 'dart:isolate';

import 'package:analyzer_plugin/protocol/protocol.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
// ignore: implementation_imports
import 'package:analyzer_plugin/src/protocol/protocol_internal.dart'
    show RequestParams;
import 'package:async/async.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A base class for the protocol responsible with interacting with using the
/// analyzer_plugin API
mixin ChannelBase {
  Stream<Object?> get _inputStream;

  /// The [Notification]s emitted by the plugin
  late final Stream<Notification> notifications = _inputStream
      .where((e) => e is Map)
      .map((e) => e! as Map)
      .where((e) => e.containsKey(Notification.EVENT))
      .map(Notification.fromJson);

  /// The [Response]s emitted by the plugin
  late final Stream<Response> responses = _inputStream
      .where((event) => event is Map<String, Object?>)
      .map((event) => event! as Map<String, Object?>)
      .where((e) => e.containsKey(Response.ID))
      .map(Response.fromJson);

  /// Error [Notification]s.
  late final Stream<PluginErrorParams> pluginErrors =
      StreamGroup.mergeBroadcast([
    // Manual error notifications from the plugin
    notifications
        .where((e) => e.event == 'plugin.error')
        .map(PluginErrorParams.fromNotification),

    // When the receivePort is passed to Isolate.onError, error events are
    // received as ["error", "stackTrace"]
    _inputStream
        .where((event) => event is List)
        .cast<List<Object?>>()
        .map((event) {
      // The plugin had an uncaught error.
      if (event.length != 2) {
        throw UnsupportedError(
          'Only ["error", "stackTrace"] list messages are supported',
        );
      }

      final error = event.first.toString();
      final stackTrace = event.last.toString();
      return PluginErrorParams(false, error, stackTrace);
    }),
  ]);

  /// Errors for [Request]s that failed.
  late final Stream<RequestError> responseErrors =
      responses.where((e) => e.error != null).map((e) => e.error!);

  /// Sends a json object to the plugin, without awaiting for an answer
  Future<void> sendJson(Map<String, Object?> json);

  /// Send a request and obtains the associated response
  Future<Response> sendRequest(
    RequestParams requestParams,
  ) async {
    final id = _uuid.v4();
    final request = requestParams.toRequest(id);
    final responseFuture = responses.firstWhere(
      (message) {
        return message.id == id;
      },
      orElse: () => throw StateError(
        'No response for request ${request.method} $id',
      ),
    );
    await sendJson(request.toJson());
    final response = await responseFuture;

    if (response.error != null) {
      throw RequestFailure(response.error!);
    }

    return response;
  }

  /// Send a request and obtains the associated response
  Future<Response> sendRequestParams(
    RequestParams requestParams,
  ) async {
    final id = _uuid.v4();

    final request = requestParams.toRequest(id);
    final responseFuture = responses.firstWhere(
      (message) => message.id == id,
      orElse: () => throw StateError(
        'No response for request ${request.method} $id',
      ),
    );
    await sendJson(request.toJson());
    final response = await responseFuture;

    if (response.error != null) {
      throw RequestFailure(response.error!);
    }

    return response;
  }
}

/// Mixin for Isolate-based channels
abstract class IsolateChannelBase with ChannelBase {
  IsolateChannelBase(this.receivePort) {
    _sendPort =
        _inputStream.where((event) => event is SendPort).cast<SendPort>().first;
  }

  /// The [ReceivePort] responsible for listening to requests.
  final ReceivePort receivePort;

  @override
  late final Stream<Object?> _inputStream = receivePort.asBroadcastStream();

  /// The [SendPort] responsible for sending events to the isolate.
  late final Future<SendPort> _sendPort;

  @override
  Future<void> sendJson(Map<String, Object?> json) {
    return _sendPort.then((value) => value.send(json));
  }
}

/// An interface for interacting with the plugin server.
class ServerIsolateChannel extends IsolateChannelBase {
  /// An interface for interacting with the plugin server.
  ServerIsolateChannel() : super(ReceivePort());

  /// Lints emitted by the plugin
  late final Stream<AnalysisErrorsParams> lints = notifications
      .where((e) => e.event == 'analysis.errors')
      .map(AnalysisErrorsParams.fromNotification);

  void close() => receivePort.close();
}
