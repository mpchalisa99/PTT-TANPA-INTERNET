import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:udp/udp.dart';
import '../models/peer_member.dart';

/// ============================================================================
/// UDP NETWORK SERVICE - 100% OFFLINE HOTSPOT MASTER & CLIENT
/// ============================================================================
/// Arsitektur Jaringan Walkie-Talkie (PTT) Lokal Tanpa Internet:
/// 1. Port Tetap (Fixed Port): 50500 (`pttPort`) untuk Broadcast & Receiver PCM Audio.
/// 2. Deteksi IP Lokal & Kalkulasi Otomatis IP Broadcast Subnet:
///    - Menggunakan `network_info_plus` + fallback `NetworkInterface.list`
///      (penting bagi HP Master Hotspot karena interface `ap0`/`wlan0`/`swlan0`
///      sering tidak terbaca oleh `getWifiIP()` saat Hotspot menyala tanpa WiFi).
///    - Mengubah IP perangkat (misal `192.168.43.5` atau `192.168.43.1`) menjadi
///      IP Broadcast subnet `/24` (`192.168.43.255`).
/// 3. UDP Broadcast Sender:
///    - Mengirim `Uint8List` Raw PCM Audio langsung ke IP Broadcast (`x.x.x.255:50500`).
/// 4. UDP Continuous Receiver & Anti-Echo (Self-IP Filtering):
///    - Mendengarkan port `50500` secara non-stop (`Endpoint.any`).
///    - Mengabaikan seluruh paket yang berasal dari IP perangkat sendiri
///      (`senderIp == _localIp` atau terdaftar di `_localInterfaceIps`) agar
///      suara sendiri tidak memantul kembali (Zero Loopback Echo).
/// ============================================================================
class UdpNetworkService extends ChangeNotifier {
  /// Requirement 1: Port UDP tetap untuk transmisi & penerimaan audio PTT
  static const int pttPort = 50500;

  /// Alias port untuk kompatibilitas modul Discovery & Audio
  static const int audioPort = pttPort;
  static const int discoveryPort = 50000;
  static const String masterDefaultIp = '192.168.43.1';
  static const String defaultBroadcastIp = '192.168.43.255';

  /// Signature Magic Header (4 byte: 'PTT1') untuk membedakan paket dengan header
  /// channel vs paket murni Raw PCM `Uint8List`.
  static const int _magicByte0 = 0x50; // 'P'
  static const int _magicByte1 = 0x54; // 'T'
  static const int _magicByte2 = 0x54; // 'T'
  static const int _magicByte3 = 0x31; // '1'

  UDP? _udpSocket;
  UDP? _discoverySocket;
  Timer? _heartbeatTimer;
  Timer? _pruneTimer;

  String _localIp = masterDefaultIp;
  String _broadcastIp = defaultBroadcastIp;
  final Set<String> _localInterfaceIps = {masterDefaultIp, '127.0.0.1'};

  String _myCallsign = 'YUDHI';
  final String _deviceId = 'NODE-${DateTime.now().millisecondsSinceEpoch % 10000}';
  int _currentChannel = 12;
  bool _isMaster = true;
  bool _talkAll = true;
  bool _isTransmitting = false;
  int _lastPingMs = 18;
  int _pingDeltaMs = 2;
  int _txSequence = 0;

  /// Daftar peer online yang terdeteksi di jaringan Hotspot (key: IP)
  final Map<String, PeerMember> _peers = {};

  /// Requirement 4: Callback saat paket suara Raw PCM diterima dari perangkat lain
  void Function(Uint8List pcmBytes, String senderIp)? onAudioPacketReceived;

  String get localIp => _localIp;
  String get broadcastIp => _broadcastIp;
  String get myCallsign => _myCallsign;
  int get currentChannel => _currentChannel;
  bool get isMaster => _localIp.trim().endsWith('.1');
  String get roleStatusText =>
      _localIp.trim().endsWith('.1') ? 'PERAN: MASTER HOST' : 'PERAN: CLIENT';
  bool get talkAll => _talkAll;
  bool get isTransmitting => _isTransmitting;
  int get lastPingMs => _lastPingMs;
  int get pingDeltaMs => _pingDeltaMs;
  bool get isHighLatency => _lastPingMs > 150;

  List<PeerMember> get activeChannelPeers => _peers.values
      .where((p) => p.channel == _currentChannel)
      .toList()
    ..sort((a, b) => a.callsign.compareTo(b.callsign));

  List<PeerMember> get targetedPeers => activeChannelPeers
      .where((p) => _talkAll || p.isTargeted)
      .toList();

  /// Inisialisasi layanan jaringan UDP (Deteksi IP Broadcast + Bind Port 50500)
  Future<void> initialize() async {
    await detectBroadcastIp();
    await _bindPttAudioSocket();
    await _bindDiscoverySocket();

    // Heartbeat auto-discovery & pembaruan IP jika jaringan Hotspot berubah
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) async {
        await detectBroadcastIp();
        await _sendDiscoveryAnnouncement();
      },
    );

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pruneStalePeers(),
    );

    await _sendDiscoveryAnnouncement();
  }

  /// --------------------------------------------------------------------------
  /// Requirement 2: Fungsi Deteksi IP Lokal & IP Broadcast WiFi / Hotspot
  /// Contoh: Jika IP HP `192.168.43.5`, maka menghasilkan `192.168.43.255`
  /// --------------------------------------------------------------------------
  Future<String> detectBroadcastIp() async {
    String? detectedLocalIp;
    String? detectedBroadcast;
    final Set<String> foundLocalIps = {'127.0.0.1'};

    try {
      final networkInfo = NetworkInfo();

      // 1. Coba ambil IP WiFi dan Broadcast langsung dari network_info_plus (untuk HP Client)
      final wifiIp = await networkInfo.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        detectedLocalIp = wifiIp;
        foundLocalIps.add(wifiIp);
      }

      final wifiBroadcast = await networkInfo.getWifiBroadcast();
      if (wifiBroadcast != null &&
          wifiBroadcast.isNotEmpty &&
          wifiBroadcast != '0.0.0.0' &&
          wifiBroadcast != '255.255.255.255') {
        detectedBroadcast = wifiBroadcast;
      }

      // 2. Fallback: Scan seluruh NetworkInterface sistem (Wajib untuk HP Master Hotspot!
      //    Saat HP menyalakan Mobile Hotspot tanpa WiFi, interface aktif berada di
      //    `ap0`, `wlan0`, `swlan0`, `softap0`, atau `rndis0` yang sering tidak terbaca getWifiIP)
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isHotspotOrWifi = name.contains('ap') ||
            name.contains('wlan') ||
            name.contains('swlan') ||
            name.contains('rndis') ||
            name.contains('eth');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          foundLocalIps.add(ip);

          // Prioritaskan IP Gateway Hotspot standar Android (192.168.43.1)
          if (ip == masterDefaultIp) {
            detectedLocalIp = masterDefaultIp;
          } else if (isHotspotOrWifi &&
              (ip.startsWith('192.168.') ||
                  ip.startsWith('172.') ||
                  ip.startsWith('10.'))) {
            detectedLocalIp ??= ip;
          } else if (detectedLocalIp == null && ip.startsWith('192.168.')) {
            detectedLocalIp = ip;
          }
        }
      }
    } catch (e) {
      debugPrint('Gagal mendeteksi NetworkInfo/NetworkInterface: $e');
    }

    _localIp = (detectedLocalIp != null && detectedLocalIp.isNotEmpty)
        ? detectedLocalIp
        : masterDefaultIp;
    foundLocalIps.add(_localIp);

    _localInterfaceIps
      ..clear()
      ..addAll(foundLocalIps);

    // Hitung IP Broadcast dari IP lokal (misal 192.168.43.5 -> 192.168.43.255)
    _broadcastIp = _calculateSubnetBroadcast(_localIp, fallback: detectedBroadcast);

    // Perangkat yang memiliki akhiran .1 pada jaringan Hotspot bertindak sebagai MASTER
    _isMaster = _localIp.endsWith('.1');
    notifyListeners();

    return _broadcastIp;
  }

  /// Mengonversi IPv4 `/24` menjadi alamat Broadcast subnet (x.x.x.255)
  String _calculateSubnetBroadcast(String ipAddress, {String? fallback}) {
    final parts = ipAddress.trim().split('.');
    if (parts.length == 4) {
      final o1 = int.tryParse(parts[0]);
      final o2 = int.tryParse(parts[1]);
      final o3 = int.tryParse(parts[2]);
      if (o1 != null && o2 != null && o3 != null) {
        return '$o1.$o2.$o3.255';
      }
    }
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return defaultBroadcastIp;
  }

  /// --------------------------------------------------------------------------
  /// Requirement 4: UDP Receiver pada Port Tetap (50500) + Anti-Echo Filter
  /// --------------------------------------------------------------------------
  Future<void> _bindPttAudioSocket() async {
    try {
      _udpSocket?.close();

      // Bind ke 0.0.0.0:50500 agar menerima seluruh paket UDP Broadcast & Unicast
      _udpSocket = await UDP.bind(Endpoint.any(port: const Port(pttPort)));

      // Mengaktifkan opsi SO_BROADCAST pada socket底层 (RawDatagramSocket)
      _udpSocket!.socket?.broadcastEnabled = true;
      _udpSocket!.socket?.writeEventsEnabled = true;

      _udpSocket!.asStream().listen(
        (Datagram? datagram) {
          if (datagram == null || datagram.data.isEmpty) return;

          final String senderIp = datagram.address.address;

          // PENTING (Anti-Echo): Abaikan paket yang berasal dari IP perangkat sendiri
          if (_isOwnIpAddress(senderIp)) {
            return;
          }

          final Uint8List rawBytes = datagram.data;

          // Cek apakah paket memiliki 10-byte Tactical Header ('PTT1' + Ch + Flags + Seq + Len)
          // atau murni Raw PCM Uint8List
          if (rawBytes.length > 10 &&
              rawBytes[0] == _magicByte0 &&
              rawBytes[1] == _magicByte1 &&
              rawBytes[2] == _magicByte2 &&
              rawBytes[3] == _magicByte3) {
            final int packetChannel = rawBytes[4];
            if (packetChannel != _currentChannel) return;

            final Uint8List pcmPayload = Uint8List.sublistView(rawBytes, 10);
            if (pcmPayload.isNotEmpty) {
              onAudioPacketReceived?.call(pcmPayload, senderIp);
            }
          } else {
            // Paket Raw PCM murni langsung diteruskan ke callback audio player
            onAudioPacketReceived?.call(rawBytes, senderIp);
          }
        },
        onError: (Object error) {
          debugPrint('UDP Receiver Error pada port $pttPort: $error');
        },
      );
    } catch (e) {
      debugPrint('Gagal membuka UDP Socket pada port $pttPort: $e');
    }
  }

  /// Mengecek apakah [senderIp] adalah milik perangkat ini sendiri
  bool _isOwnIpAddress(String senderIp) {
    if (senderIp == _localIp || senderIp == '127.0.0.1' || senderIp == '0.0.0.0') {
      return true;
    }
    return _localInterfaceIps.contains(senderIp);
  }

  /// --------------------------------------------------------------------------
  /// Requirement 3: UDP Sender untuk Mengirim (Broadcast) Raw PCM Audio
  /// ke IP Broadcast Jaringan Saat Ini (misal 192.168.43.255:50500)
  /// --------------------------------------------------------------------------
  Future<void> broadcastRawPcmAudio(Uint8List pcmBytes) async {
    if (_udpSocket == null || pcmBytes.isEmpty) return;

    try {
      // Pastikan broadcastEnabled aktif pada socket
      _udpSocket!.socket?.broadcastEnabled = true;

      // Kirim langsung ke Subnet Broadcast (contoh: 192.168.43.255:50500)
      final broadcastEndpoint = Endpoint.unicast(
        InternetAddress(_broadcastIp),
        port: const Port(pttPort),
      );

      await _udpSocket!.send(pcmBytes, broadcastEndpoint);
    } catch (e) {
      debugPrint('Gagal broadcast PCM audio ke $_broadcastIp:$pttPort -> $e');
    }
  }

  /// Mengirim chunk audio PCM dengan header channel taktikal ke IP Broadcast
  /// (Digunakan oleh tombol PTT utama agar mendukung multi-channel & bebas collision)
  Future<void> sendRawAudioChunk(Uint8List pcmChunk) async {
    if (_udpSocket == null || pcmChunk.isEmpty) return;

    _txSequence = (_txSequence + 1) & 0xFFFF;

    // Header 10-Byte:
    // Byte 0..3 : Magic 'PTT1' (0x50, 0x54, 0x54, 0x31)
    // Byte 4    : Channel (1-99)
    // Byte 5    : Flags (Bit 0 = Master, Bit 1 = TalkAll)
    // Byte 6..7 : Sequence Number (Uint16 Big Endian)
    // Byte 8..9 : Panjang PCM Payload (Uint16 Big Endian)
    final header = ByteData(10);
    header.setUint8(0, _magicByte0);
    header.setUint8(1, _magicByte1);
    header.setUint8(2, _magicByte2);
    header.setUint8(3, _magicByte3);
    header.setUint8(4, _currentChannel);
    header.setUint8(5, (_isMaster ? 1 : 0) | (_talkAll ? 2 : 0));
    header.setUint16(6, _txSequence, Endian.big);
    header.setUint16(8, pcmChunk.length, Endian.big);

    final packet = Uint8List(10 + pcmChunk.length);
    packet.setRange(0, 10, header.buffer.asUint8List());
    packet.setRange(10, packet.length, pcmChunk);

    try {
      _udpSocket!.socket?.broadcastEnabled = true;

      // 1. Kirim UDP Broadcast ke Subnet Hotspot (misal 192.168.43.255:50500)
      await _udpSocket!.send(
        packet,
        Endpoint.unicast(
          InternetAddress(_broadcastIp),
          port: const Port(pttPort),
        ),
      );
    } catch (e) {
      debugPrint('Broadcast audio ke $_broadcastIp gagal: $e');
    }

    // 2. Fallback Unicast ke Gateway Master (.1) & peer yang ditargetkan
    //    (Menjamin suara tetap tembus meskipun AP Isolation aktif di beberapa tipe HP)
    final parts = _localIp.split('.');
    final gatewayIp = parts.length == 4
        ? '${parts[0]}.${parts[1]}.${parts[2]}.1'
        : masterDefaultIp;

    final Set<String> unicastTargets = {
      if (!_isMaster) gatewayIp,
      ...targetedPeers.map((p) => p.ipAddress),
    }..removeWhere(_isOwnIpAddress);

    for (final targetIp in unicastTargets) {
      try {
        await _udpSocket!.send(
          packet,
          Endpoint.unicast(
            InternetAddress(targetIp),
            port: const Port(pttPort),
          ),
        );
      } catch (_) {}
    }
  }

  /// --------------------------------------------------------------------------
  /// SOCKET AUTO-DISCOVERY & PING ANGGOTA (UDP PORT 50000)
  /// --------------------------------------------------------------------------
  Future<void> _bindDiscoverySocket() async {
    try {
      _discoverySocket?.close();
      _discoverySocket = await UDP.bind(
        Endpoint.any(port: const Port(discoveryPort)),
      );
      _discoverySocket!.socket?.broadcastEnabled = true;

      _discoverySocket!.asStream().listen((Datagram? datagram) {
        if (datagram == null) return;
        final senderIp = datagram.address.address;
        if (_isOwnIpAddress(senderIp)) return;

        try {
          final payload = utf8.decode(datagram.data);
          final Map<String, dynamic> data = jsonDecode(payload);
          final String type = (data['type'] ?? '').toString();

          if (type == 'ANNOUNCE') {
            final incoming = PeerMember.fromJson(data);
            final existing = _peers[senderIp];
            if (existing != null) {
              incoming.isTargeted = existing.isTargeted;
              incoming.lastPingMs = existing.lastPingMs;
            }
            _peers[senderIp] = incoming;
            notifyListeners();
          } else if (type == 'PING') {
            _sendPong(senderIp, (data['ts'] as num).toInt());
          } else if (type == 'PONG') {
            final sentTs = (data['ts'] as num).toInt();
            final rtt = DateTime.now().millisecondsSinceEpoch - sentTs;
            _pingDeltaMs = rtt - _lastPingMs;
            _lastPingMs = rtt.clamp(1, 999);
            if (_peers.containsKey(senderIp)) {
              _peers[senderIp]!.lastPingMs = _lastPingMs;
            }
            notifyListeners();
          }
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Gagal bind discovery socket port $discoveryPort: $e');
    }
  }

  Future<void> _sendDiscoveryAnnouncement() async {
    if (_discoverySocket == null) return;

    final packet = jsonEncode({
      'type': 'ANNOUNCE',
      'id': _deviceId,
      'callsign': _myCallsign,
      'ip': _localIp,
      'ch': _currentChannel,
      'master': _isMaster,
      'talking': _isTransmitting,
    });
    final bytes = utf8.encode(packet);

    try {
      _discoverySocket!.socket?.broadcastEnabled = true;
      await _discoverySocket!.send(
        bytes,
        Endpoint.unicast(
          InternetAddress(_broadcastIp),
          port: const Port(discoveryPort),
        ),
      );
    } catch (_) {}
  }

  Future<void> refreshPing() async {
    if (_discoverySocket == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final bytes = utf8.encode(jsonEncode({'type': 'PING', 'ts': now}));

    for (final peer in _peers.values) {
      try {
        await _discoverySocket!.send(
          bytes,
          Endpoint.unicast(
            InternetAddress(peer.ipAddress),
            port: const Port(discoveryPort),
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _sendPong(String targetIp, int originalTs) async {
    if (_discoverySocket == null) return;
    final bytes = utf8.encode(jsonEncode({'type': 'PONG', 'ts': originalTs}));
    try {
      await _discoverySocket!.send(
        bytes,
        Endpoint.unicast(
          InternetAddress(targetIp),
          port: const Port(discoveryPort),
        ),
      );
    } catch (_) {}
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    _peers.removeWhere((_, peer) => now.difference(peer.lastSeen).inSeconds > 7);
    notifyListeners();
  }

  void setChannel(int newChannel) {
    _currentChannel = newChannel.clamp(1, 99);
    _sendDiscoveryAnnouncement();
    notifyListeners();
  }

  void setCallsign(String newName) {
    if (newName.trim().isEmpty) return;
    _myCallsign = newName.trim().toUpperCase();
    _sendDiscoveryAnnouncement();
    notifyListeners();
  }

  void toggleTalkAll() {
    _talkAll = !_talkAll;
    if (_talkAll) {
      for (final p in _peers.values) {
        p.isTargeted = true;
      }
    }
    notifyListeners();
  }

  void togglePeerTarget(String ip) {
    final peer = _peers[ip];
    if (peer != null) {
      peer.isTargeted = !peer.isTargeted;
      _talkAll = _peers.values.every((p) => p.isTargeted);
      notifyListeners();
    }
  }

  void setTransmitting(bool value) {
    _isTransmitting = value;
    _sendDiscoveryAnnouncement();
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _pruneTimer?.cancel();
    _udpSocket?.close();
    _discoverySocket?.close();
    super.dispose();
  }
}
