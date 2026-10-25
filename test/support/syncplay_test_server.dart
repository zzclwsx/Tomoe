import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Small protocol fixture using real TCP framing and the upstream permission
/// rules. It deliberately sends initial state before Hello, as Syncplay can.
class SyncplayTestServer {
  late ServerSocket _server;
  final peers = <TestPeer>[];
  final playlists = <String, List<String>>{};
  final passwords = <String, String>{};
  final states = <String, ({double position, bool paused, String actor})>{};
  int controls = 0;
  String get endpoint => '127.0.0.1:${_server.port}';
  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((socket) {
      unawaited(socket.done.catchError((_) {}));
      final peer = TestPeer(socket);
      peers.add(peer);
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _receive(peer, jsonDecode(line) as Map<String, dynamic>),
            onDone: () => _leave(peer),
            onError: (_) => _leave(peer),
          );
    });
  }

  void _send(TestPeer p, Map<String, dynamic> data) {
    p.writes = p.writes
        .then((_) async {
          if (!peers.contains(p)) return;
          p.socket.write('${jsonEncode(data)}\r\n');
          await p.socket.flush();
        })
        .catchError((_) {});
  }

  void _broadcast(String room, Map<String, dynamic> data) {
    for (final peer in peers.where((p) => p.room == room)) {
      _send(peer, data);
    }
  }

  void _leave(TestPeer peer) {
    final room = peer.room;
    if (!peers.remove(peer)) return;
    _broadcast(room, {
      'Set': {
        'user': {
          peer.name: {
            'event': {'left': true},
          },
        },
      },
    });
  }

  void _initial(TestPeer p) {
    _send(p, {
      'Set': {
        'playlistChange': {'user': p.room, 'files': playlists[p.room] ?? []},
      },
    });
    sendState(p.room);
  }

  void _receive(TestPeer p, Map<String, dynamic> data) {
    if (data['Hello'] case final Map hello) {
      p.name = hello['username'] as String;
      p.room = (hello['room'] as Map)['name'] as String;
      _initial(p);
      _send(p, {
        'Hello': {
          'username': p.name,
          'room': {'name': p.room},
          'features': {
            'managedRooms': true,
            'sharedPlaylists': true,
            'chat': true,
            'maxChatMessageLength': 150,
          },
        },
      });
      _broadcast(p.room, {
        'Set': {
          'user': {
            p.name: {
              'event': {'joined': true},
            },
          },
        },
      });
    }
    if (data.containsKey('List')) {
      _send(p, {
        'List': {
          p.room: {
            for (final other in peers.where((x) => x.room == p.room))
              other.name: {'controller': other.controller},
          },
        },
      });
    }
    if (data['Chat'] case final String text) {
      _broadcast(p.room, {
        'Chat': {'username': p.name, 'message': text},
      });
    }
    if (data['Set'] case final Map settings) {
      if (settings['room'] case final Map room) {
        p.room = room['name'] as String;
        p.controller = false;
        _send(p, {
          'Set': {
            'user': {
              p.name: {
                'room': {'name': p.room},
              },
            },
          },
        });
        _initial(p);
      }
      if (settings['controllerAuth'] case final Map auth) {
        final target = auth['room'] as String;
        final password = auth['password'] as String;
        if (!RegExp(r'^[A-Z]{2}-[0-9]{3}-[0-9]{3}$').hasMatch(password)) {
          _send(p, {
            'Set': {
              'controllerAuth': {
                'user': p.name,
                'room': p.room,
                'success': false,
              },
            },
          });
          return;
        }
        if (!target.startsWith('+')) {
          final managed = '+$target:0123456789ab';
          passwords[managed] = password;
          _send(p, {
            'Set': {
              'newControlledRoom': {'roomName': managed, 'password': password},
            },
          });
        } else {
          p.controller = passwords[target] == password && target == p.room;
          _broadcast(p.room, {
            'Set': {
              'controllerAuth': {
                'user': p.name,
                'room': p.room,
                'success': p.controller,
              },
            },
          });
        }
      }
      if (settings['playlistChange'] case final Map playlist) {
        if (!p.room.startsWith('+') || p.controller) {
          final files = (playlist['files'] as List).cast<String>();
          playlists[p.room] = files;
          _broadcast(p.room, {
            'Set': {
              'playlistChange': {'user': p.name, 'files': files},
            },
          });
        }
      }
    }
    if (data['State'] case final Map state) {
      if ((state['ignoringOnTheFly'] as Map?)?.containsKey('client') == true) {
        final play = state['playstate'] as Map;
        if (!p.room.startsWith('+') || p.controller) {
          controls++;
          states[p.room] = (
            position: (play['position'] as num).toDouble(),
            paused: play['paused'] as bool,
            actor: p.name,
          );
        }
        final ack = (state['ignoringOnTheFly'] as Map)['client'];
        for (final other in peers.where((x) => x.room == p.room)) {
          _sendState(
            other,
            force: play['doSeek'] == true,
            ack: identical(p, other) ? ack as int : null,
          );
        }
      }
    }
  }

  void _sendState(TestPeer p, {bool force = false, int? ack}) {
    final state =
        states[p.room] ?? (position: 0.0, paused: true, actor: 'Nobody');
    _send(p, {
      'State': {
        'playstate': {
          'position': state.position,
          'paused': state.paused,
          'setBy': state.actor,
          'doSeek': force,
        },
        'ping': {'serverRtt': 0},
        if (ack != null) 'ignoringOnTheFly': {'client': ack},
      },
    });
  }

  void sendState(String room) {
    for (final peer in peers.where((x) => x.room == room)) {
      _sendState(peer);
    }
  }

  Future<void> fragmentedChat(String text) async {
    final data = utf8.encode(
      '${jsonEncode({
        'Chat': {'username': 'Friend', 'message': text},
      })}\r\n',
    );
    final split = data.indexWhere((byte) => byte > 127) + 1;
    for (final peer in peers) {
      peer.writes = peer.writes.then((_) async {
        peer.socket.add(data.sublist(0, split));
        await peer.socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        peer.socket.add(data.sublist(split));
        await peer.socket.flush();
      });
      await peer.writes;
    }
  }

  Future<void> close() async {
    for (final peer in peers.toList()) {
      peer.socket.destroy();
    }
    peers.clear();
    await _server.close();
  }
}

class TestPeer {
  TestPeer(this.socket);
  final Socket socket;
  String name = '';
  String room = '';
  bool controller = false;
  Future<void> writes = Future.value();
}

Future<void> eventually(bool Function() predicate) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed > const Duration(seconds: 3)) {
      throw StateError('Condition did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
